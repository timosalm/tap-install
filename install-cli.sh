#!/bin/bash

case "${1:linux}" in
	darwin) PRODUCT_ID=1212837;;
	linux) PRODUCT_ID=1212839;;
esac

pivnet download-product-files --product-slug='tanzu-application-platform' --release-version='1.1.1' --product-file-id=$PRODUCT_ID
mkdir tanzu
tar -xvf "tanzu-framework-$1-amd64.tar" -C tanzu
export TANZU_CLI_NO_INIT=true
cd tanzu
sudo install "cli/core/v0.11.4/tanzu-core-$1_amd64" /usr/local/bin/tanzu
tanzu version

tanzu plugin install --local cli all
tanzu plugin list
cd ..