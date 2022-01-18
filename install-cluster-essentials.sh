#!/bin/bash

pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.0.0' --product-file-id=1105818
mkdir tanzu-cluster-essentials
tar -xvf tanzu-cluster-essentials-linux-amd64-1.0.0.tgz -C tanzu-cluster-essentials

export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:82dfaf70656b54dcba0d4def85ccae1578ff27054e7533d08320244af7fb0343
export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$(cat values.yaml | grep tanzunet -A 3 | awk '/username:/ {print $2}')
export INSTALL_REGISTRY_PASSWORD=$(cat values.yaml  | grep tanzunet -A 3 | awk '/password:/ {print $2}')

cd tanzu-cluster-essentials
./install.sh
cd ..