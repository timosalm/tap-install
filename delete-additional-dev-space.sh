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

kapp delete --yes --app "tap-dev-ns-${DEVELOPER_NAMESPACE}-grype" --namespace tap-install
kapp delete --yes --app "tap-dev-ns-${DEVELOPER_NAMESPACE}-auth" --namespace tap-install
kapp delete --yes --app "tap-dev-ns-${DEVELOPER_NAMESPACE}-reg-creds" --namespace tap-install
kapp delete --yes --app "tap-dev-ns-${DEVELOPER_NAMESPACE}" --namespace tap-install
