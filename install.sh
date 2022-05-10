#!/bin/bash

set -e
set -u
set -o pipefail

# base everything relative to the directory of this script file
script_dir="$(cd $(dirname "$BASH_SOURCE[0]") && pwd)"

generated_dir="${script_dir}/generated"
mkdir -p "${generated_dir}"

values_file_default="${script_dir}/values.yaml"
values_file=${VALUES_FILE:-$values_file_default}

export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$(yq '.tanzunet.username' < "${values_file}")
export INSTALL_REGISTRY_PASSWORD=$(yq '.tanzunet.password' < "${values_file}")

kapp deploy \
  --app tap-install-ns \
  --file <(\
    kubectl create namespace tap-install \
      --dry-run=client \
      --output=yaml \
      --save-config \
    ) \
  --yes

DEVELOPER_NAMESPACE=$(yq '.developer_namespace' < "${values_file}")

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

tanzu secret registry \
  --namespace tap-install \
  add tap-registry \
  --username "${INSTALL_REGISTRY_USERNAME}" \
  --password "${INSTALL_REGISTRY_PASSWORD}" \
  --server "${INSTALL_REGISTRY_HOSTNAME}" \
  --export-to-all-namespaces \
  --yes

tanzu package repository \
  --namespace tap-install \
  add tanzu-tap-repository \
  --url registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:1.1.1

tanzu package repository \
  --namespace tap-install \
  get tanzu-tap-repository

ytt -f "${script_dir}/tap-values.yaml" -f "${values_file}" --ignore-unknown-comments > "${generated_dir}/tap-values.yaml"

kapp deploy \
  --app tap-overlay-cnrs-network \
  --namespace tap-install \
  --file <(\
    kubectl create secret generic tap-pkgi-overlay-0-cnrs-network-config \
      --namespace tap-install \
      --from-file="tap-pkgi-overlay-0-cnrs-network-config.yaml=${script_dir}/overlays/cnrs/tap-pkgi-overlay-0-cnrs-network-config.yaml" \
      --dry-run=client \
      --output=yaml \
      --save-config \
  ) \
  --yes

tanzu package install tap \
  --namespace tap-install \
  --package-name tap.tanzu.vmware.com \
  --version 1.1.1 \
  --values-file "${generated_dir}/tap-values.yaml"

# Use HTTPS instead of HTTP in the output of the application URL
kubectl annotate packageinstalls tap \
  --namespace tap-install \
  --overwrite \
  ext.packaging.carvel.dev/ytt-paths-from-secret-name.0=tap-pkgi-overlay-0-cnrs-network-config

# install external dns
# check that the namespace set in .ingress.contour_tls_namespace already exists
contour_tls_namespace=$(yq '.ingress.contour_tls_namespace' < "${values_file}")
kubectl get namespace | cut -d' ' -f1 | grep -E "^${contour_tls_namespace}$" || exit 2

kapp deploy \
  --app external-dns \
  --namespace tap-install \
  --file <(\
     ytt --ignore-unknown-comments -f values.yaml -f ${script_dir}/ingress-config/external-dns \
  ) \
  --yes

kapp deploy \
  --app lets-encrypt-issuer \
  --namespace tap-install \
  --file <(\
     ytt --ignore-unknown-comments -f values.yaml -f ${script_dir}/ingress-config/lets-encrypt-issuer \
  ) \
  --yes

kapp deploy \
  --app certificates \
  --namespace tap-install \
  --file <(\
     ytt --ignore-unknown-comments -f values.yaml -f ${script_dir}/ingress-config/certificates \
  ) \
  --yes

kapp deploy \
  --app ingress \
  --namespace tap-install \
  --file <(\
     ytt --ignore-unknown-comments -f values.yaml -f ${script_dir}/ingress-config/ingress \
  ) \
  --yes

# configure initial developer namespace
"${script_dir}/configure-dev-space.sh" "$DEVELOPER_NAMESPACE"
