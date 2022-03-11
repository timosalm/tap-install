#!/bin/bash

if [ -z "$1" ]
  then
    echo "No argument for the developer namespace supplied"
    exit 1
fi

kubectl create ns $1
export CONTAINER_REGISTRY_HOSTNAME=$(cat values.yaml | grep container_registry -A 5 | awk '/hostname:/ {print $2}')
export CONTAINER_REGISTRY_USERNAME=$(cat values.yaml | grep container_registry -A 5 | awk '/username:/ {print $2}')
export CONTAINER_REGISTRY_PASSWORD=$(cat values.yaml | grep container_registry -A 5 | awk '/password:/ {print $2}')
kubectl create secret docker-registry registry-credentials --docker-server=${CONTAINER_REGISTRY_HOSTNAME} --docker-username=${CONTAINER_REGISTRY_USERNAME} --docker-password=${CONTAINER_REGISTRY_PASSWORD} -n $1

cat <<EOF  | kubectl apply -n $1 -f -
apiVersion: v1
kind: Secret
metadata:
  name: tap-registry
  annotations:
    secretgen.carvel.dev/image-pull-secret: ""
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: e30K

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
secrets:
  - name: registry-credentials
imagePullSecrets:
  - name: registry-credentials
  - name: tap-registry

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: default
rules:
- apiGroups: [source.toolkit.fluxcd.io]
  resources: [gitrepositories]
  verbs: ['*']
- apiGroups: [source.apps.tanzu.vmware.com]
  resources: [imagerepositories]
  verbs: ['*']
- apiGroups: [carto.run]
  resources: [deliverables, runnables]
  verbs: ['*']
- apiGroups: [kpack.io]
  resources: [images]
  verbs: ['*']
- apiGroups: [conventions.apps.tanzu.vmware.com]
  resources: [podintents]
  verbs: ['*']
- apiGroups: [""]
  resources: ['configmaps']
  verbs: ['*']
- apiGroups: [""]
  resources: ['pods']
  verbs: ['list']
- apiGroups: [tekton.dev]
  resources: [taskruns, pipelineruns]
  verbs: ['*']
- apiGroups: [tekton.dev]
  resources: [pipelines]
  verbs: ['list']
- apiGroups: [kappctrl.k14s.io]
  resources: [apps]
  verbs: ['*']
- apiGroups: [serving.knative.dev]
  resources: ['services']
  verbs: ['*']
- apiGroups: [servicebinding.io]
  resources: ['servicebindings']
  verbs: ['*']
- apiGroups: [services.apps.tanzu.vmware.com]
  resources: ['resourceclaims']
  verbs: ['*']
- apiGroups: [scanning.apps.tanzu.vmware.com]
  resources: ['imagescans', 'sourcescans']
  verbs: ['*']
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: default
subjects:
  - kind: ServiceAccount
    name: default
EOF
cat <<EOF  | kubectl apply -n tap-install -f -
apiVersion: packaging.carvel.dev/v1alpha1
kind: PackageInstall
metadata:
  name: ${1}-grype
spec:
  serviceAccountName: tap-install-sa
  packageRef:
    refName: grype.scanning.apps.tanzu.vmware.com
    versionSelection:
      constraints: ">=0.0.0"
      prereleases:
        identifiers: [beta, build]
  values:
  - secretRef:
      name: ${1}-grype-values
---
apiVersion: v1
kind: Secret
metadata:
  name: ${1}-grype-values
stringData:
  values.yaml: |
    ---
    namespace: ${1}
    scanner:
      pullSecret: ""
    targetImagePullSecret: registry-credentials
EOF