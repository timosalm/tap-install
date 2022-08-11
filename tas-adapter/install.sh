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

TAS_ADAPTER_PACKAGE_VERSION=0.9.0
TAS_ADAPTER_REPO_VERSION="${TAS_ADAPTER_PACKAGE_VERSION}"

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
  --url "registry.tanzu.vmware.com/app-service-adapter/tas-adapter-package-repo:${TAS_ADAPTER_REPO_VERSION}"


tanzu package install tas-adapter \
  --namespace tap-install \
  --package-name application-service-adapter.tanzu.vmware.com \
  --version "${TAS_ADAPTER_PACKAGE_VERSION}" \
  --values-file "${generated_dir}/tas-adapter-values.yaml"

kapp deploy \
  --app tas-adapter-cf-admin \
  --namespace tap-install \
  --file <(\
     ytt --ignore-unknown-comments -f "${values_file}" -f "${script_dir}/admin" \
  ) \
  --yes
