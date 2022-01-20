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

pivnet download-product-files --product-slug='supply-chain-security-tools' --release-version='v1.0.0-beta.4' --product-file-id=1130458
chmod +x insight-1.0.1_darwin_amd64
sudo install insight-1.0.1_darwin_amd64 /usr/local/bin/insight
cd ..