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

./configure-dev-space.sh $DEVELOPER_NAMESPACE

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
