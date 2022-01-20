#!/bin/bash

pivnet download-product-files --product-slug='tanzu-application-platform' --release-version='1.0.0' --product-file-id=1114447
mkdir tanzu
rm -rf ~/Library/Application\ Support/tanzu-cli
mkdir ~/Library/Application\ Support/tanzu-cli
tar -xvf tanzu-framework-linux-amd64.tar -C tanzu
export TANZU_CLI_NO_INIT=true
cd tanzu
sudo install cli/core/v0.10.0/tanzu-core-linux_amd64 /usr/local/bin/tanzu
sudo install cli/core/v0.10.0/tanzu-core-linux_amd64 /usr/local/bin/tanzu
tanzu version

tanzu plugin install --local cli all
tanzu plugin list
cd ..