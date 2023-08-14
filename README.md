# Flux2 GitOps on Kubernetes

## Manage Kubernetes Clusters with GitOps
The purpose of creating this repository is to use Flux GitOps to manage Kubernetes clusters. It includes everything required to deploy into a Kubernetes cluster, such as infrastructure's helm releases, application's manifests.

## Tools Used for This Repo
- Kubernetes Cluster =  AKS/Kubeadm provisioned Kubernetes cluster on Azure.
- Flux = Bootstrap and orchestrate the deployments.
- Mozilla SOPA = SOPA encrypts Kubernetes secrets with OpenPGP to store secrets safely in a public or private Git repository.

## Prerequisites
- Kubernetes cluster
- Kubectl installed
- FluxCD installed, refer to [FluxCD Installation](https://fluxcd.io/flux/installation/)
- A Git repository with a personal token auth.
- Mozilla SOPS installed, refer to [Manage Kubernetes secrets with Mozilla SOPS](https://fluxcd.io/flux/guides/mozilla-sops/)

## Repository Structure
This repository uses monorepo approach to store all Kubernetes manifests in a single Git repository.
The structure is organized in this way.

```
|── clusters
|   ├── production
|   └── staging
|── infra
|   ├── base 
|   ├── production
|   └── staging
|── system
|   ├── base 
|   ├── production
|   └── staging
|── apps
|   ├── base 
|   ├── production
|   └── staging
|── 3rd
|   ├── base 
|   ├── production
|   └── staging
```

Top level
- `clusters` directory has Flux bootstrap configuration per cluster (production/staging)
- `infra` directory has platform level Kubernetes manifests related to storage, monitoring and ingress controller, currrently it has `Prometheus`, `Memcached`, `Ingress Nginx`, `Cert-Manager`, `CSI` driver and `Velero`.
- `system` directory has system level Kubernetes manifests including, `Linkerd`, `Istio`, `Jaeger`, `Redis`, `Postgres`, `Loki`,`Flagger` and `Chaos Mesh` etc.
- `apps` directory has application related manifests
- `3rd` directory has 3rd application related manifests and it is used to kustomize configuration

The separation between `infra`, `system`, `apps` and `3rd` makes it possible to define the order in which a cluster is reconciled, `infra` should keep untouched, `system` depends on `infra`, both `apps` and `3rd` depend on `system`. 

Under `infra`, `system`, `apps` and `3rd` directories, 
- `base` directory serves as the base layer for `staging` and `production` environments. Each sub-directory under `base` has the Kubernetes manifests for an application with common configurations.
- `staging` and `production` directories maps to `staging` and `production` environments, they are overlay layers of `base`, each sub-directory under them has customized configurations for same application under `base` directory.

## How It Works
Flux enables application deployment (CD) through automatic reconciliation with pull-based mode.

Flux applies manifests stored at Git repository. It leverages [kustomize](https://kubectl.docs.kubernetes.io/references/kustomize/) for fetching, decrypting, building, validating and applying manifests. 

Use podinfo for example.
- `apps/base/podinfo`, it contains base Kubernetes manifests for podinfo application, including `Namespace`, `Deployment`, `HorizontalPodAutoscaler`, `Service` and `Ingress`. 
- `apps/staging/podinfo` creates an overlay on top of `apps/base/podinfo`, it merges resources from `apps/base/podinfo`, then customizes `Ingress` object with specific FQDN, encrypts it by using sops then writes output into ingress.enc.yaml. When Flux reconciles resources, ingress.enc.yaml is decrypted automatically and gets deployed along with other resources.

It is common that one Flux resource relies on another Flux resource, for example, one `HelmRelease` relies on the presence of a Custom Resource Definition installed by another `HelmRelease`, to those kind of dependency management, Flux provides below support
- `spec.dependsOn`, available from `Kustomization` and `HelmRelease`, `spec.dependsOn` can only apply to same kind of resource, for example `Kustomization` depends on ``Kustomization`
- `spec.healthChecks`, support cross resource dependency, for example, `Kustomization` can use `spec.healthChecks` to wait until `HelmRelease` is ready.

Sample case
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1beta2
kind: Kustomization
metadata:
  name: system
  namespace: flux-system
spec:
  interval: 10m0s
  # Kustomization depends on another Kustomization resource
  dependsOn:
    - name: infra
  # Kustomization depends on HelmRelease
  healthChecks:
  - apiVersion: helm.toolkit.fluxcd.io/v2beta1
    kind: HelmRelease
    name: prometheus
    namespace: monitoring
  - apiVersion: helm.toolkit.fluxcd.io/v2beta1
    kind: HelmRelease
    name: ingress-nginx
    namespace: ingress-nginx
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./system/staging
  prune: true
```

## NOTEs

### Flux Installation
Follow this [guide](https://fluxcd.io/flux/installation/) to install Flux.

Common steps to bootstrap Flux.
```bash
# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token
export GITHUB_TOKEN=PERSONAL_ACCESS_TOKEN
# personal or organization account
export GITHUB_USER=ACCOUNT

# if account is organization, remove --personal
flux bootstrap github \
  --components-extra=image-reflector-controller,image-automation-controller \
  --owner=$GITHUB_USER \
  --repository=<YOUR_REPO> \
  --branch=main \
  --path=./clusters/staging \
  --read-write-key \
  --personal
```

Flux bootstrap doesn't care where the Git repository is, if the repository location is changed (e.g., transfer ownership to another organization), the only thing needs to do is re-run bootstrap and point `--owner` to new user/organization.

During bootstrap, Flux creates a secret named flux-system at flux-system namespace, it is used to read/write Git repository, for example, if Git repository provider is github, this secret is actually a github repository deploy key. This secret can be updated by deleting it and re-run bootstrap, this trick is useful when automate image update, as default bootstrap creates deploy key with read permission, automate image update requires write permission to commit changes, to do that, run `kubectl -n flux-system delete secret flux-system` and re-run bootstrap.  

### Manage Secrets and Sensitive Information
Flux natively supports [Mozilla SOPS](https://github.com/mozilla/sops) to encrypted files. To store Kubernetes secret safely or protect sensitive information over a public/private Git repository, here are common steps to [Manage Kubernetes secrets with Mozilla SOPS](https://fluxcd.io/flux/guides/mozilla-sops/)
- Install gnupg and SOPS
- Generate a GPG key
- Retrieve the GPG key fingerprint
- Export the public and private keypair from your local GPG keyring and create a Kubernetes secret named sops-gpg in the flux-system namespace
  ```bash
  gpg --export-secret-keys --armor GPG_KEY_FINGERPRINT |
  kubectl create secret generic sops-gpg \
  --namespace=flux-system \
  --from-file=sops.asc=/dev/stdin  
  ```
- Update `Kustomization` resource files to decrypt secrets with SOPS
  ```yaml
  apiVersion: kustomize.toolkit.fluxcd.io/v1beta2
  kind: Kustomization
  metadata:
    name: apps
    namespace: flux-system
  spec:
    # ...
    # SOPS decryption 
    decryption:
      provider: sops
      secretRef:
        name: sops-gpg
  ```
- Under directory where Kubernetes manifests contain secret/sensitive data, create a file named `.sops.yaml` and add below content 
  ```yaml
  creation_rules:
    - path_regex: .*.yaml
      encrypted_regex: ^(FIELD_TO_ENCRYPT_1|...|FIELD_TO_ENCRYPT_N)$
      pgp: GPG_KEY_FINGERPRINT
  ```
- To protect from committing original file accidently, add a .gitignore file in same directory then add original file's name into it
- Use command `sops -e --input-type=yaml --output-type=yaml filename.yaml > filename.enc.yaml` to encrypt the file
- Start to reference `filename.enc.yaml` in other Kubernetes resource files

As a best practice, consider of exporting the public key to the repository so that other team members can use the same public key to encrypt the new files. 
```shell
gpg --export --armor "${KEY_FP}" > ./clusters/staging/.sops.pub.asc
```

Check into the git
```shell
git add ./clusters/staging/.sops.pub.asc
git commit -am 'Share GPG public key for secrets generation'
```

Restore encryption and decryption key
```shell
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod a+x /usr/local/bin/yq
gpg --import ./clusters/staging/.sops.pub.asc
kubectl get secret sops-gpg -n flux-system -o yaml | yq -r '.data."sops.asc"' | base64 -d > .sops.asc
gpg --import .sops.asc
```

### Pin Specific Version in GitOps
There are a few good reasons you may want to pin a specific version in GitOps:
- Reproducibility - Pinning specific versions (e.g. tags, commits) ensures you can redeploy the exact same app version repeatedly. This is great for testing or diagnosing issues with a specific build.
- Stability - You may want to pin a known good, stable version of an app to a production environment. This prevents unexpected changes or regressions from syncing.
- Compliance - In regulated environments like healthcare, you often need to lock down specific approved versions of an application. Pinning versions can satisfy compliance requirements.
- Rollbacks - If a bad version is deployed, you can easily rollback by pointing the GitOps config back to a previous good version.
- Promotions - You can promote versions through environments by updating the pinned version as you move from dev to staging to production.
- Testing - Pinning versions allows you to safely test specific builds in lower environments without impacting production.
- Independent environments - Pinning uniques versions lets you isolate environments and prevent bad changes from spreading across dev, staging, prod.
So in summary, version pinning gives you control, stability and reproducibilty. It's a best practice for using GitOps to manage a change management workflow across environments.

The repo includes a sample of pinning a specific version, refer to postgres sample `system/base/postgres` and `system/staging/postgres` for details, in `staging`, we pinned postgres version to a specific version number 12.5.2, this is done through adding a patch section into kustomization.yaml
```
patches:
  - path: release.yaml
    target:
      kind: HelmRelease
```

### Webhook Receivers
Flux can be configured to receive changes in Git and trigger a cluster reconciliation every time a source changes. To expose the webhook receiver endpoint, we can create an `Ingress`

When use cert-manager to request certificate for `Ingress` used by [Webhook Receivers](https://fluxcd.io/flux/guides/webhook-receivers/), certificate request won't be succeeded, cert-manager and ingress controller will keep reporting 504 error, below is sample log from cert-manager

`E1208 06:37:38.717038       1 sync.go:190] cert-manager/challenges "msg"="propagation check failed" "error"="wrong status code '504', expected '200'" "dnsName"="flux-webhook.example.com" "resource_kind"="Challenge" "resource_name"="flux-webhook-tls-vmb44-803982081-2270031681" "resource_namespace"="flux-system" "resource_version"="v1" "type"="HTTP-01"`

This is because network policy created at flux-system namespace `allow-webhooks` during flux bootstrap, only allows inbound traffic to pod with label `app=notification-controller`, when cert-manager notices an ingress object is created at flux-system namespace, it creates a pod named with cm-acme-http-solver-xxxxx in same namespace, as there is no network policy to allow inbound traffic to this pod, HTTP01 challenges fails. To work around this issue, consider of adding a new network policy to allow inbound HTTP01 challenges, below is an example
```yaml
# Filename allow-acme-solver.yaml
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

### Automate Image Updates to Git
This article [Automate image updates to Git](https://fluxcd.io/flux/guides/image-update/) provides detailed steps to configure image update, when creates `ImageUpdateAutomation` to write image update to Git repository, a few things need to take care

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
      # Reference GitRepository namespace 
      namespace: flux-system 
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
      # Point to manifest directory
      path: ./apps/staging/echo-mirror 
      strategy: Setters
  ```

### Prometheus Monitoring

#### ETCD, Kube Controller Manager and Kube Scheduler Monitoring

From community [issue](https://github.com/prometheus-operator/kube-prometheus/issues/718#issue-717603994)

From kubernetes master node, updating etcd.yaml in /etc/kubernetes/manifests/ to use the --listen-metrics-urls=http://0.0.0.0:2381 for ETCD.

From kubernetes master node, updating kube-controller-manager.yaml and kube-scheduler.yaml in /etc/kubernetes/manifests/ to use the --bind-address 0.0.0.0 for both the scheduler and the controller manager.

Restart pods

```bash
kubectl delete pod -l component=etcd -n kube-system
kubectl delete pod -l component=kube-controller-manager -n kube-system
kubectl delete pod -l component=kube-scheduler -n kube-system
```

Above steps will relaunch the the pods with the correct bind address, but these settings will not survive a kubeadm upgrade.

In order to persist the settings, the kubeadm-config configmap in the kube-system namespace should also be edited to include the following:

```bash
kubectl edit cm kubeadm-config -n kube-system
```

```yaml
    controllerManager:
      extraArgs:
        bind-address: 0.0.0.0
    scheduler:
      extraArgs:
        bind-address: 0.0.0.0
    etcd:
      local:
        extraArgs:
          listen-metrics-urls: http://0.0.0.0:2381
```

#### Kube Proxy Monitoring

```bash
kubectl edit cm/kube-proxy -n kube-system
```
```yaml
...
kind: KubeProxyConfiguration
## Change from
## metricsBindAddress: 127.0.0.1:10249
## Change to
metricsBindAddress: 0.0.0.0:10249
...
```

```bash
kubectl delete pod -l k8s-app=kube-proxy -n kube-system
```

#### Prometheus Alerting Rules

[Awesome Prometheus Alerts](https://github.com/samber/awesome-prometheus-alerts)

#### Grafana Dashboards
kube-prometheus-stack helm chart includes a collection of Grafana dashboards, besides of those default dashboards, here is a list of used Grafana dashboards in this repository

NGINX Ingress controller
(https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/grafana/dashboards/nginx.json)
[Request Handling Performance](https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/grafana/dashboards/request-handling-performance.json)

[Redis](https://grafana.com/grafana/dashboards/12776-redis/), requires [Redis Grafana Plugin](https://grafana.com/grafana/plugins/redis-datasource/) to be installed

[Memcached](https://grafana.com/grafana/dashboards/11527-memcached-overview/)

[PostgreSQL](https://grafana.com/grafana/dashboards/9628-postgresql-database/)

[Grafana Loki Dashboard for NGINX Service Mesh](https://grafana.com/grafana/dashboards/12559-grafana-loki-dashboard-for-nginx-service-mesh/)

### Velero Backup
```bash
# Start the sample nginx app
kubectl apply -f https://raw.githubusercontent.com/vmware-tanzu/velero/main/examples/nginx-app/with-pv.yaml
# Create a backup
velero backup create nginx-backup --include-namespaces nginx-example
# Verify backup is completed
velero backup describe nginx-backup
# Simulate a disaster
kubectl delete namespaces nginx-example
# Restore your lost resources
velero restore create --from-backup nginx-backup
# Delete backup
velero backup delete nginx-backup
# Delete sample ngix app again
kubectl delete namespaces nginx-example
```

## Workload Identity

```bash
# environment variables for issuer configuration
export SUBSCRIPTION_ID=<REPLACE_ME>
export AZURE_STORAGE_ACCOUNT=<REPLACE ME>
export AZURE_STORAGE_CONTAINER=<REPLACE ME>
export RESOURCE_GROUP="AZWI"
export LOCATION="eastus"

# setup public OIDC issuer URL using Azure blob storage and upload a minimal discovery document to the storage account.
az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}"
az storage account create --resource-group "${RESOURCE_GROUP}" --name "${AZURE_STORAGE_ACCOUNT}"
az storage container create --name "${AZURE_STORAGE_CONTAINER}" --public-access container

cat <<EOF > openid-configuration.json
{
  "issuer": "https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net/${AZURE_STORAGE_CONTAINER}/",
  "jwks_uri": "https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net/${AZURE_STORAGE_CONTAINER}/openid/v1/jwks",
  "response_types_supported": [
    "id_token"
  ],
  "subject_types_supported": [
    "public"
  ],
  "id_token_signing_alg_values_supported": [
    "RS256"
  ]
}
EOF

az storage blob upload \
  --container-name "${AZURE_STORAGE_CONTAINER}" \
  --account-name "${AZURE_STORAGE_ACCOUNT}" \
  --file openid-configuration.json \
  --name .well-known/openid-configuration

azwi jwks --public-keys /etc/kubernetes/pki/sa.pub --output-file jwks.json

az storage blob upload \
  --container-name "${AZURE_STORAGE_CONTAINER}" \
  --account-name "${AZURE_STORAGE_ACCOUNT}" \
  --file jwks.json \  
  --name openid/v1/jwks

export SERVICE_ACCOUNT_ISSUER=https://$AZURE_STORAGE_ACCOUNT.blob.core.windows.net/$AZURE_STORAGE_CONTINERAINER

sed -i "s#service-account-issuer=https://kubernetes.default.svc.cluster.local#service-account-issuer=$SERVICE_ACCOUNT_ISSUER#g" /etc/kubernetes/manifests/kube-apiserver.yaml


# install workload-identity-webhook helm chart
export AZURE_TENANT_ID="$(az account show -s "${SUBSCRIPTION_ID}" --query tenantId -o tsv)"
helm install workload-identity-webhook azure-workload-identity/workload-identity-webhook \ 
   --namespace azure-workload-identity-system \
   --set azureTenantID="${AZURE_TENANT_ID}"

# environment variables for the Azure Key Vault resource
export KEYVAULT_NAME="azwi-kv-eus"
export KEYVAULT_SECRET_NAME="azwi-secret"
export USER_ASSIGNED_IDENTITY_NAME="azwi-k8sea"
export SERVICE_ACCOUNT_NAMESPACE="azwi"
export SERVICE_ACCOUNT_NAME="workload-identity-sa"

az keyvault create --resource-group "${RESOURCE_GROUP}" \
   --location "${LOCATION}" \        
   --name "${KEYVAULT_NAME}"

az keyvault secret set --vault-name "${KEYVAULT_NAME}" \
   --name "${KEYVAULT_SECRET_NAME}" \
   --value "Hello\!"

az identity create --name "${USER_ASSIGNED_IDENTITY_NAME}" --resource-group "${RESOURCE_GROUP}"  --location "${LOCATION}"

export USER_ASSIGNED_IDENTITY_CLIENT_ID="$(az identity show --name "${USER_ASSIGNED_IDENTITY_NAME}" --resource-group "${RESOURCE_GROUP}" --query 'clientId' -o tsv)"

az keyvault set-policy --name "${KEYVAULT_NAME}" \
  --secret-permissions get \
  --spn "${USER_ASSIGNED_IDENTITY_CLIENT_ID}"

kubectl create ns $SERVICE_ACCOUNT_NAMESPACE

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: ${APPLICATION_CLIENT_ID:-$USER_ASSIGNED_IDENTITY_CLIENT_ID}
  labels:
    azure.workload.identity/use: "true"
  name: ${SERVICE_ACCOUNT_NAME}
  namespace: ${SERVICE_ACCOUNT_NAMESPACE}
EOF

az identity federated-credential create \
  --name "k8sea-federated-credential" \
  --identity-name "${USER_ASSIGNED_IDENTITY_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --issuer "${SERVICE_ACCOUNT_ISSUER}" \
  --subject "system:serviceaccount:${SERVICE_ACCOUNT_NAMESPACE}:${SERVICE_ACCOUNT_NAME}"

export KEYVAULT_URL="$(az keyvault show -g ${RESOURCE_GROUP} -n ${KEYVAULT_NAME} --query properties.vaultUri -o tsv)"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: azwi
  namespace: ${SERVICE_ACCOUNT_NAMESPACE}
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: ${SERVICE_ACCOUNT_NAME}
  containers:
    - image: ghcr.io/azure/azure-workload-identity/msal-go
      name: oidc
      env:
      - name: KEYVAULT_URL
        value: ${KEYVAULT_URL}
      - name: SECRET_NAME
        value: ${KEYVAULT_SECRET_NAME}
  nodeSelector:
    kubernetes.io/os: linux
EOF

# clean up
kubectl delete -n "${SERVICE_ACCOUNT_NAMESPACE}"
az group delete --name "${RESOURCE_GROUP}"
```

```json
{
  "alg": "RS256",
  "kid": "xnML5UVEOmaXhc6C961EArSm86kIdXfjTisuL2q6JV0"
}.{
  "aud": [
    "https://k8sea.blob.core.windows.net/oidc"
  ],
  "exp": 1702294296,
  "iat": 1670758296,
  "iss": "https://k8sea.blob.core.windows.net/oidc",
  "kubernetes.io": {
    "namespace": "azwi",
    "pod": {
      "name": "azwi",
      "uid": "72ed5f47-e3a0-48a4-94dc-ea955b765097"
    },
    "serviceaccount": {
      "name": "workload-identity-sa",
      "uid": "a410f479-480a-4a6f-aa31-0fd0ec78b6af"
    },
    "warnafter": 1670761903
  },
  "nbf": 1670758296,
  "sub": "system:serviceaccount:azwi:workload-identity-sa"
}.[Signature]
```

## Troubleshooting
### Fix "upgrade retries exhausted"
If seeing below errors
`flux get helmreleases -A`
NAMESPACE                     	NAME                     	REVISION	SUSPENDED	READY  	MESSAGE                          
```
dapr-system                   	dapr                     	1.10.7  	False    	False  	upgrade retries exhausted       	
```  

Try using those commands to fix the issue
```bash
flux suspend hr <helmreleae name> -n <namespace>
flux resume hr <helmreleae name> -n <namespace>
```
