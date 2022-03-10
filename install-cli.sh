#!/bin/bash

case "${1:linux}" in
	darwin) PRODUCT_ID=1156167;;
	linux) PRODUCT_ID=1156168;;
esac

pivnet download-product-files --product-slug='tanzu-application-platform' --release-version='1.0.2' --product-file-id=$PRODUCT_ID
mkdir tanzu
tar -xvf "tanzu-framework-$1-amd64.tar" -C tanzu
export TANZU_CLI_NO_INIT=true
cd tanzu
sudo install "cli/core/v0.11.1/tanzu-core-$1_amd64" /usr/local/bin/tanzu
tanzu version

tanzu plugin install --local cli all
tanzu plugin list
cd ..