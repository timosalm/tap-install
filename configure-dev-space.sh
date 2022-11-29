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
kind: RoleBinding
metadata:
  name: default-permit-deliverable
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: deliverable
subjects:
- kind: ServiceAccount
  name: default

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: default-permit-workload
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: workload
subjects:
- kind: ServiceAccount
  name: default

EOF