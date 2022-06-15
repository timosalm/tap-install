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

TAS_ADAPTER_VERSION=0.7.0

export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$(yq '.tanzunet.username' < "${values_file}")
export INSTALL_REGISTRY_PASSWORD=$(yq '.tanzunet.password' < "${values_file}")

ytt -f "${script_dir}/tas-adapter-values.yaml" -f "${values_file}" --ignore-unknown-comments > "${generated_dir}/tas-adapter-values.yaml"

kapp deploy \
  --app tas-adapter-certificates \
  --namespace tap-install \
  --file <(\
     ytt --ignore-unknown-comments -f "${values_file}" -f "${script_dir}/additional-ingress-config" \
  ) \
  --yes

tanzu package repository \
  --namespace tap-install \
  add tas-adapter-repository \
  --url "registry.tanzu.vmware.com/app-service-adapter/tas-adapter-package-repo:${TAS_ADAPTER_VERSION}"


# swallow error on initial package installation because the schema validation will fail
tanzu package install tas-adapter \
  --namespace tap-install \
  --package-name application-service-adapter.tanzu.vmware.com \
  --version "${TAS_ADAPTER_VERSION}" \
  --values-file "${generated_dir}/tas-adapter-values.yaml" \
|| true

# Due to a bug with the ordering of files in ytt version 0.38.0, the schema override doesn't work and we have to specify the full schema in the schema-overlay.yaml before the override as a workaround!
kapp deploy \
  --app tas-adapter-overlay-ingress \
  --namespace tap-install \
  --file <(\
    kubectl create secret generic tas-adapter-overlay-ingress \
      --namespace tap-install \
      --from-file=ingress-overlay.yaml=${script_dir}/overlays/tas-adapter/ingress-overlay.yaml \
      --from-file=configuration-overlay.yaml=${script_dir}/overlays/tas-adapter/configuration-overlay.yaml \
      --from-file=schema-overlay.yaml=${script_dir}/overlays/tas-adapter/schema-overlay.yaml \
      --dry-run=client \
      --output=yaml \
      --save-config \
  ) \
  --yes

kubectl annotate packageinstalls tas-adapter \
  --namespace tap-install \
  --overwrite \
  ext.packaging.carvel.dev/ytt-paths-from-secret-name.0=tas-adapter-overlay-ingress

kapp deploy \
  --app tas-adapter-cf-admin \
  --namespace tap-install \
  --file <(\
     ytt --ignore-unknown-comments -f "${values_file}" -f "${script_dir}/admin" \
  ) \
  --yes

# Delete korifi-controllers-controller-manager pod so that configuration changes take effect
INGRESS_SECRET=$(yq '.ingress.contour_tls_secret' < "${values_file}")
OVERRIDEN_CONFIG=$(kubectl get cm -n korifi-controllers-system -o jsonpath='{.items[*].data}')
until grep -q "$INGRESS_SECRET" <<< "$OVERRIDEN_CONFIG";
do
  echo "Waiting until config override applied..."
  sleep 1
  OVERRIDEN_CONFIG=$(kubectl get cm -n korifi-controllers-system -o jsonpath='{.items[*].data}')
done
kubectl delete pods -l control-plane=controller-manager -n korifi-controllers-system
