# Flux2 GitOps on Kubernetes

## Manage Kubernetes Clusters with Gitops
The purpose of creating this repo is to use Flux GitOps to manage my kubernetes clusters. This repo has everything including infrastructure helm releases, application manifests, even with sensitive data such as secrets and credentials (encrypted with Mozilla SOPS).

## Tools used for this repo are:
- K8S Cluster =  AKS/Kubeadm provisioned kubernetes cluster on Azure.
- FluxCD = Flux bootstrap to orchestrate the deployments.
- Mozilla SOPA = SOPA encrypts Kubernetes secrets with OpenPGP to store secrets safely in a public or private Git repository.

## Prerequisites
- Kubernetes cluster.
- Kubectl installed on your machine.
- FluxCD installed on your machine, refer to [FluxCD Installation](https://fluxcd.io/flux/installation/)
- A Git repos with a personal token auth.
- Mozilla SOPS, refer to [Manage Kubernetes secrets with Mozilla SOPS](https://fluxcd.io/flux/guides/mozilla-sops/)

## Repository structure
This Git repository contains the following top directories:

- infrastructure directory contains common kubernetes infra components such as prometheus, loki, ingress controller, storage drivers, linkerd service mesh with other helm repository definitions including postgresql and redis etc.
- apps directory contains kustomization releases of applications
- clusters directry contains the flux bootstrap configuration per cluster (production/staging)

```
|── clusters
|   ├── production
|   └── staging
|── infrastructure
|   ├── base 
|   ├── production
|   └── staging
|── apps
|   ├── base 
|   ├── production
|   └── staging
```

Under *infrastructure* and *apps* directoris, *base* directory contains a set of resources which will be used by *staging* and *production* environments, *staging* and *production* composes resources from *base* and may also have customization on top of it.

## How it works
Flux enables application deployment (CD) and (with the help of Flagger) progressive delivery (PD) through automatic reconciliation.

Manifests are stored into git repo and get applied by Flux. The Kustomization API defines a pipeline for fetching, decrypting, building, validating and applying Kustomize overlays or plain Kubernetes manifests. 

Take *apps/base/podinfo* for instance, it contains base resources for podinfo application, including kubernetes namespace, deployment, hpa, service and ingress object. *apps/staging/podinfo* creates an overlay layer on top of *apps/base/podinfo*, it customizes the ingress object with specific host fqdn name, use sops to encrypt host fqdn related fileds and store them into ingress.enc.yaml. When Flux reconciles resources from *apps/staging/podinfo*, ingress.enc.yaml will be decryted on the fly, then get merged with base layer resources and deployed.

## Notice

### Webhook Receivers
Flux can be configured to receive changes in Git and trigger a cluster reconciliation every time a source changes. To expose the webhook receiver endpoint, we can create an `Ingress`

When use cert-manager to request certificate for `Ingress` used by [Webhook Receivers](https://fluxcd.io/flux/guides/webhook-receivers/), certificate request won't be succeeded, cert-manager and ingress controller will keep reporting 504 error, below is sample log from cert-manager


`E1208 06:37:38.717038       1 sync.go:190] cert-manager/challenges "msg"="propagation check failed" "error"="wrong status code '504', expected '200'" "dnsName"="flux-webhook.example.com" "resource_kind"="Challenge" "resource_name"="flux-webhook-tls-vmb44-803982081-2270031681" "resource_namespace"="flux-system" "resource_version"="v1" "type"="HTTP-01"`

This is because network policy created at flux-system namespace `allow-webhooks` during flux bootstrap, only allows inbound traffic to pod with label `app=notification-controller`, when cert-manager notices an ingress object is created at flux-system namespace, it creates a pod named with cm-acme-http-solver-xxxxx in same namespace, as there is no network policy to allow inbound traffic to this pod, HTTP01 challenges fails. To work around this issue, consider of adding a new network policy to allow inbound HTTP01 challenges, below is an example
```yaml
# allow-acme-solver.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-acme-solver
spec:
  ingress:
  - from:
    - namespaceSelector: {}
  podSelector:
    matchLabels:
      acme.cert-manager.io/http01-solver: "true"
  policyTypes:
  - Ingress
```

### Automate image updates to Git
This article [Automate image updates to Git](https://fluxcd.io/flux/guides/image-update/) provies detailed steps to configure image update, when creates `ImageUpdateAutomation` to write image update to Git repository, a few things need to take care

- All three resources `ImageRepository`, `ImagePolicy` and `ImageUpdateAutomation` must be in same namespace, this is because currently ImageUpdateAutomation will only list ImagePolicy in same namespace.

- Point `path` field to the manifest directory where the update is going to write. For example, GitRepository might point to ./cluster/staging, but the deployment.yaml file is at ./apps/staging/echo-mirror, the `path` field should set to ./apps/staging/echo-mirror.

- Add `namespace` under `sourceRef` if `GitRepository` resource is created at different namespace. For example, `GitRepository` flux-system is created at flux-system namespace, while `ImageUpdateAutomation` echo-mirror is created at echo-mirror namespace, a `namespace` field has to be added so `ImageUpdateAutomation` can find `GitRepository` correctly.

Below is an example

  ```yaml
  apiVersion: image.toolkit.fluxcd.io/v1beta1
  kind: ImageUpdateAutomation
  metadata:
    name: echo
  spec:
    interval: 1m0s
    sourceRef:
      kind: GitRepository
      name: flux-system
      namespace: flux-system # namespace reference
    git:
      checkout:
        ref:
          branch: main
      commit:
        author:
          email: fluxcdbot@users.noreply.github.com
          name: fluxcdbot
        messageTemplate: '{{range .Updated.Images}}{{println .}}{{end}}'
      push:
        branch: main
    update:
      path: ./apps/staging/echo-mirror # manifest directory
      strategy: Setters
  ```