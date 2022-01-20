#!/bin/bash

mkdir -p generated/keys

export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$(cat values.yaml | grep tanzunet -A 3 | awk '/username:/ {print $2}')
export INSTALL_REGISTRY_PASSWORD=$(cat values.yaml  | grep tanzunet -A 3 | awk '/password:/ {print $2}')
export VALUES_YAML=values-example.yaml


if [ $(yq e .provider-config.dns $VALUES_YAML) = "gcloud-dns" ] && [ $(yq e .provider-config.k8s $VALUES_YAML) != "tkg" ];
then

  kubectl create ns tanzu-kapp
  kubectl create namespace tanzu-system-service-discovery
  
  kubectl -n tanzu-system-service-discovery create secret \
      generic gcloud-dns-credentials \
      --from-file=credentials.json=generated/keys/gcloud-dns-credentials.json \
      -o yaml --dry-run=client | kubectl apply -f-
  
  ytt --ignore-unknown-comments -f values.yaml -f config/gcloud/external-dns-gcloud-values.yaml  > generated/external-dns-gcloud-values.yaml
  tanzu package repository add tanzu-standard --url projects.registry.vmware.com/tkg/packages/standard/repo:v1.4.0 -n tanzu-kapp
  VERSION=$(tanzu package available list external-dns.tanzu.vmware.com -oyaml -n tanzu-kapp| yq eval ".[0].version" -)
  tanzu package install external-dns \
      --package-name external-dns.tanzu.vmware.com \
      --version $VERSION \
      --namespace tanzu-kapp \
      --values-file generated/external-dns-gcloud-values.yaml \
      --poll-timeout 10m0s

fi


kubectl create ns tap-install
tanzu secret registry add tap-registry \
  --username ${INSTALL_REGISTRY_USERNAME} --password ${INSTALL_REGISTRY_PASSWORD} \
  --server ${INSTALL_REGISTRY_HOSTNAME} \
  --export-to-all-namespaces --yes --namespace tap-install
tanzu package repository add tanzu-tap-repository \
  --url registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:1.0.0 \
  --namespace tap-install
tanzu package repository get tanzu-tap-repository --namespace tap-install

ytt -f tap-values.yaml -f values.yaml --ignore-unknown-comments > generated/tap-values.yaml

DEVELOPER_NAMESPACE=$(cat values.yaml  | grep developer_namespace | awk '/developer_namespace:/ {print $2}')
kubectl create ns $DEVELOPER_NAMESPACE

tanzu package install tap -p tap.tanzu.vmware.com -v 1.0.0 --values-file generated/tap-values.yaml -n tap-install



if [ $(yq e .provider-config.dns $VALUES_YAML) = "gcloud-dns" ];
then

  CLOUD_DNS_SA=certmgr-cdns-admin-$(date +%s)
  gcloud --project $PROJECT_ID iam service-accounts create $CLOUD_DNS_SA \
      --display-name "Service Account to support ACME DNS-01 challenge."
  CLOUD_DNS_SA=$CLOUD_DNS_SA@$PROJECT_ID.iam.gserviceaccount.com
  gcloud projects add-iam-policy-binding $PROJECT_ID \
       --member serviceAccount:$CLOUD_DNS_SA \
       --role roles/dns.admin
  gcloud iam service-accounts keys create generated/keys/key.json  --iam-account $CLOUD_DNS_SA
  kubectl create secret generic clouddns-dns01-solver-svc-acct -n cert-manager \
     --from-file=generated/keys/key.json
  
  ytt --ignore-unknown-comments -f values.yaml -f config/cert-ingress | kubectl apply -f-
  ytt --ignore-unknown-comments -f values.yaml -f config/gcloud/lets-encrypt-cluster-issuer.yaml | kubectl apply -f-

fi

if [ $(yq e .provider-config.dns $VALUES_YAML) = "aws" ];
then

  # install external dns
  kubectl create ns tanzu-system-ingress
  ytt --ignore-unknown-comments -f values.yaml -f config/aws | kubectl apply -f-
  ytt --ignore-unknown-comments -f values.yaml -f config/cert-ingress | kubectl apply -f-

fi



# configure developer namespace
export CONTAINER_REGISTRY_HOSTNAME=$(cat values.yaml | grep container_registry -A 3 | awk '/hostname:/ {print $2}')
export CONTAINER_REGISTRY_USERNAME=$(cat values.yaml | grep container_registry -A 3 | awk '/username:/ {print $2}')
export CONTAINER_REGISTRY_PASSWORD=$(cat values.yaml | grep container_registry -A 3 | awk '/password:/ {print $2}')
#tanzu secret registry add registry-credentials --username ${CONTAINER_REGISTRY_USERNAME} --password ${CONTAINER_REGISTRY_PASSWORD} --server ${CONTAINER_REGISTRY_HOSTNAME} --namespace ${DEVELOPER_NAMESPACE}
kubectl create secret docker-registry registry-credentials --docker-server=$CONTAINER_REGISTRY_HOSTNAME --docker-username=$CONTAINER_REGISTRY_USERNAME --docker-password=$CONTAINER_REGISTRY_PASSWORD -n $DEVELOPER_NAMESPACE
ytt --ignore-unknown-comments -f values.yaml -f config/dev-ns-prep | kubectl apply -f-

# configure 
ytt --ignore-unknown-comments -f values.yaml -f demo/ | kubectl apply -f-