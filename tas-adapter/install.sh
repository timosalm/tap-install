#!/bin/bash
mkdir -p generated

ytt --ignore-unknown-comments -f values.yaml -f additonal-ingress-config/ | kubectl apply -f-

sudo wget -O /etc/yum.repos.d/cloudfoundry-cli.repo https://packages.cloudfoundry.org/fedora/cloudfoundry-cli.repo
sudo yum install cf8-cli
cf version

kubectl create ns tas-adapter-install

export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$(cat values.yaml | grep tanzunet -A 3 | awk '/username:/ {print $2}')
export INSTALL_REGISTRY_PASSWORD=$(cat values.yaml  | grep tanzunet -A 3 | awk '/password:/ {print $2}')
tanzu secret registry add tap-registry \
  --username ${INSTALL_REGISTRY_USERNAME} --password ${INSTALL_REGISTRY_PASSWORD} \
  --server ${INSTALL_REGISTRY_HOSTNAME} \
  --namespace tas-adapter-install

tanzu package repository add tas-adapter-repository \
  --url registry.tanzu.vmware.com/app-service-adapter/tas-adapter-package-repo:0.2.0 \
  --namespace tas-adapter-install
ytt -f tas-adapter-values.yaml -f values.yaml --ignore-unknown-comments > generated/tas-adapter-values.yaml
tanzu package install tas-adapter \
  --package-name application-service-adapter.tanzu.vmware.com \
  --version 0.2.0 \
  --values-file generated/tas-adapter-values.yaml \
  --namespace tas-adapter-install

INGRESS_TLS_SECRET_NAME=$(cat values.yaml | grep ingress -A 3 | awk '/contour_tls_secret:/ {print $2}')
INGRESS_TLS_SECRET_NAMESPACE=$(cat values.yaml | grep ingress -A 3 | awk '/contour_tls_namespace:/ {print $2}')
cp overlays/tas-adapter/ingress-overlay.yaml generated/ingress-overlay.yaml
sed -i"" -e "s/INGRESS_TLS_SECRET_NAMESPACE/$INGRESS_TLS_SECRET_NAMESPACE/" generated/ingress-overlay.yaml
sed -i"" -e "s/INGRESS_TLS_SECRET_NAME/$INGRESS_TLS_SECRET_NAME/" generated/ingress-overlay.yaml
kubectl create secret generic ingress-secret-name-overlay --from-file=ingress-secret-name-overlay.yaml=generated/ingress-overlay.yaml -n tas-adapter-install
kubectl annotate packageinstalls tas-adapter -n tas-adapter-install ext.packaging.carvel.dev/ytt-paths-from-secret-name.0=ingress-secret-name-overlay

DEFAULT_APP_MEMORY_ALLOCATION=$(cat values.yaml  | grep default_app_memory_allocation | awk '/default_app_memory_allocation:/ {print $2}')
cp overlays/tas-adapter/workload-configuration-overlay.yaml generated/workload-configuration-overlay.yaml
sed -i"" -e "s/INGRESS_TLS_SECRET_NAMESPACE/$INGRESS_TLS_SECRET_NAMESPACE/" generated/workload-configuration-overlay.yaml
sed -i"" -e "s/INGRESS_TLS_SECRET_NAME/$INGRESS_TLS_SECRET_NAME/" generated/workload-configuration-overlay.yaml
sed -i"" -e "s/DEFAULT_APP_MEMORY_ALLOCATION/$DEFAULT_APP_MEMORY_ALLOCATION/" generated/workload-configuration-overlay.yaml
kubectl create secret generic workload-configuration-overlay --from-file=workload-configuration-overlay.yaml=generated/workload-configuration-overlay.yaml -n tas-adapter-install
kubectl annotate packageinstalls tas-adapter -n tas-adapter-install ext.packaging.carvel.dev/ytt-paths-from-secret-name.1=workload-configuration-overlay
# Delete cf-k8s-controllers-controller-manager pod so that configuration changes take effect 
DEFAULT_APP_MEMORY_ALLOCATION=$(cat values.yaml  | grep default_app_memory_allocation | awk '/default_app_memory_allocation:/ {print $2}')
OVERRIDEN_CONFIG=$(kubectl get cm cf-k8s-controllers-config -n cf-k8s-controllers-system -o jsonpath='{.data}')
until grep -q "$DEFAULT_APP_MEMORY_ALLOCATION" <<< "$OVERRIDEN_CONFIG";
do
  echo "Waiting until config override happend ..."
  sleep 1
  OVERRIDEN_CONFIG=$(kubectl get cm cf-k8s-controllers-config -n cf-k8s-controllers-system -o jsonpath='{.data}')
done
kubectl delete pods -l control-plane=controller-manager -n cf-k8s-controllers-system

export CONTAINER_REGISTRY_HOSTNAME=$(cat values.yaml | grep container_registry -A 3 | awk '/hostname:/ {print $2}')
export CONTAINER_REGISTRY_USERNAME=$(cat values.yaml | grep container_registry -A 3 | awk '/username:/ {print $2}')
export CONTAINER_REGISTRY_PASSWORD=$(cat values.yaml | grep container_registry -A 3 | awk '/password:/ {print $2}')
kubectl create secret docker-registry image-registry-credentials \
  -n cf \
  --docker-server=${CONTAINER_REGISTRY_HOSTNAME} \
  --docker-username=${CONTAINER_REGISTRY_USERNAME} \
  --docker-password=${CONTAINER_REGISTRY_PASSWORD}
