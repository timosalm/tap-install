#!/bin/bash

set -e
set -u
set -o pipefail

if [ -z "$1" ]
  then
    echo "No argument for the developer namespace supplied"
    exit 1
fi

# base everything relative to the directory of this script file
script_dir="$(cd $(dirname "$BASH_SOURCE[0]") && pwd)"

values_file_default="${script_dir}/values.yaml"
values_file=${VALUES_FILE:-$values_file_default}

DEVELOPER_NAMESPACE=${1}

kapp deploy \
  --app "tap-dev-ns-${DEVELOPER_NAMESPACE}" \
  --namespace tap-install \
  --file <(\
    kubectl create namespace "${DEVELOPER_NAMESPACE}" \
      --dry-run=client \
      --output=yaml \
      --save-config \
    ) \
  --yes

export CONTAINER_REGISTRY_HOSTNAME=$(yq '.container_registry.hostname' < "${values_file}")
export CONTAINER_REGISTRY_USERNAME=$(yq '.container_registry.username' < "${values_file}")
export CONTAINER_REGISTRY_PASSWORD=$(yq '.container_registry.password' < "${values_file}")

kapp deploy \
  --app "tap-dev-ns-${DEVELOPER_NAMESPACE}-reg-creds" \
  --namespace tap-install \
  --file <(\
    kubectl create secret docker-registry registry-credentials \
      "--docker-server=${CONTAINER_REGISTRY_HOSTNAME}" \
      "--docker-username=${CONTAINER_REGISTRY_USERNAME}" \
      "--docker-password=${CONTAINER_REGISTRY_PASSWORD}" \
      "--namespace=${DEVELOPER_NAMESPACE}" \
      --dry-run=client \
      --output=yaml \
      --save-config \
    ) \
  --yes

cat <<EOF | kapp deploy --yes --app "tap-dev-ns-${DEVELOPER_NAMESPACE}-auth" --namespace tap-install --into-ns "${DEVELOPER_NAMESPACE}" --file -
apiVersion: v1
kind: Secret
metadata:
  name: tap-registry
  annotations:
    secretgen.carvel.dev/image-pull-secret: ""
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: e30K

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
secrets:
  - name: registry-credentials
imagePullSecrets:
  - name: registry-credentials
  - name: tap-registry

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: default
rules:
- apiGroups: [source.toolkit.fluxcd.io]
  resources: [gitrepositories]
  verbs: ['*']
- apiGroups: [source.apps.tanzu.vmware.com]
  resources: [imagerepositories]
  verbs: ['*']
- apiGroups: [carto.run]
  resources: [deliverables, runnables]
  verbs: ['*']
- apiGroups: [kpack.io]
  resources: [images]
  verbs: ['*']
- apiGroups: [conventions.apps.tanzu.vmware.com]
  resources: [podintents]
  verbs: ['*']
- apiGroups: [""]
  resources: ['configmaps']
  verbs: ['*']
- apiGroups: [""]
  resources: ['pods']
  verbs: ['list']
- apiGroups: [tekton.dev]
  resources: [taskruns, pipelineruns]
  verbs: ['*']
- apiGroups: [tekton.dev]
  resources: [pipelines]
  verbs: ['list']
- apiGroups: [kappctrl.k14s.io]
  resources: [apps]
  verbs: ['*']
- apiGroups: [serving.knative.dev]
  resources: ['services']
  verbs: ['*']
- apiGroups: [servicebinding.io]
  resources: ['servicebindings']
  verbs: ['*']
- apiGroups: [services.apps.tanzu.vmware.com]
  resources: ['resourceclaims']
  verbs: ['*']
- apiGroups: [scanning.apps.tanzu.vmware.com]
  resources: ['imagescans', 'sourcescans']
  verbs: ['*']
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: default
subjects:
  - kind: ServiceAccount
    name: default
EOF

cat <<EOF | kapp deploy --yes --app "tap-dev-ns-${DEVELOPER_NAMESPACE}-grype" --namespace tap-install --into-ns tap-install --file -
apiVersion: packaging.carvel.dev/v1alpha1
kind: PackageInstall
metadata:
  name: ${DEVELOPER_NAMESPACE}-grype
spec:
  serviceAccountName: tap-install-sa
  packageRef:
    refName: grype.scanning.apps.tanzu.vmware.com
    versionSelection:
      constraints: ">=0.0.0"
      prereleases:
        identifiers: [beta, build]
  values:
  - secretRef:
      name: ${DEVELOPER_NAMESPACE}-grype-values
---
apiVersion: v1
kind: Secret
metadata:
  name: ${DEVELOPER_NAMESPACE}-grype-values
stringData:
  values.yaml: |
    ---
    namespace: ${DEVELOPER_NAMESPACE}
    scanner:
      pullSecret: ""
    targetImagePullSecret: registry-credentials
EOF
