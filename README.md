# Flux2 GitOps on Kubernetes
### Manage Kubernetes Clusters with Gitops
The purpose of creating this repo is to use Flux GitOps to manage my kubernetes clusters. This repo has everything including infrastructure helm releases, application manifests, even with sensitive data such as secrets and credentials (encrypted with Mozilla SOPS).

### Tools used for this repo are:
- K8S Cluster =  AKS/Kubeadm provisioned kubernetes cluster on Azure.
- FluxCD = Flux bootstrap to orchestrate the deployments.
- Mozilla SOPA = SOPA encrypts Kubernetes secrets with OpenPGP to store secrets safely in a public or private Git repository.

### Prerequisites
- Kubernetes cluster.
- Kubectl installed on your machine.
- FluxCD installed on your machine, refer to [FluxCD Installation](https://fluxcd.io/flux/installation/)
- A Git repos with a personal token auth.
- Mozilla SOPS, refer to [Manage Kubernetes secrets with Mozilla SOPS](https://fluxcd.io/flux/guides/mozilla-sops/)

### Repository structure
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

### How it works
Flux enables application deployment (CD) and (with the help of Flagger) progressive delivery (PD) through automatic reconciliation.

Manifests are stored into git repo and get applied by Flux. The Kustomization API defines a pipeline for fetching, decrypting, building, validating and applying Kustomize overlays or plain Kubernetes manifests. 

Take *apps/base/podinfo* for instance, it contains base resources for podinfo application, including kubernetes namespace, deployment, hpa, service and ingress object. *apps/staging/podinfo* creates an overlay layer on top of *apps/base/podinfo*, it customizes the ingress object with specific host fqdn name, use sops to encrypt host fqdn related fileds and store them into ingress.enc.yaml. When Flux reconciles resources from *apps/staging/podinfo*, ingress.enc.yaml will be decryted on the fly, then get merged with base layer resources and deployed.
