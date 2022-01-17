# Unofficial TAP 1.0 installation guide 

This installation guide should help you to install TAP 1.0 with wildcard certificates and [enternal-dns](https://github.com/kubernetes-sigs/external-dns) to a Kubernetes cluster.

It's always recommended to go through the official documentation in addition to this guide!
The scripts and commands in this guide were executed on a Amazon Linux 2 jumpbox. It's recommended to go through them step by step!

To also install the [Application Service Adapter for VMware Tanzu Application Platform public beta](https://tanzu.vmware.com/content/blog/application-service-adapter-for-vmware-tanzu-application-platform-2), you can follow the instructions [here](tas-adapter) after the installation of TAP.

## Resources
 - [1.0 documentation](https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-overview.html)

## Prerequisities
- [Pivnet CLI](https://github.com/pivotal-cf/pivnet-cli#installing)
- You have to create the following private projects in Harbor `tap`, `tap-wkld`. For other registries you may have to change the format of the `kp_default_repository` and `ootb_supply_chain_testing_scanning.registry.repository` configuration values in `tap-values.yaml` 

## Provision a Kubernetes cluster

The scripts are currently only validated with GKE!

### GKE

It looks like there is an [issue](https://jira.eng.vmware.com/browse/TANZUSC-821) with GKE during the installation where the cluster is overloaded even if there are enough resources available and it goes several times into a repair state / requests to the Kubernetes API timeout. You just have to wait for some time until every sub-package is in `ReconcileSucceeded` state.

With the following commands, you can provision a cluster with the [gcloud CLI](https://cloud.google.com/sdk/docs/install).
```
CLUSTER_ZONE=europe-west3-a
gcloud container clusters create tap --zone $CLUSTER_ZONE --cluster-version "1.21.5-gke.1302" --machine-type "e2-standard-4" --num-nodes "4" --node-locations $CLUSTER_ZONE
gcloud container clusters get-credentials tap --zone $CLUSTER_ZONE
```

## Install Cluster Essentials for VMware Tanzu

[Documentation](https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-install-general.html#tanzu-cluster-essentials)

The Cluster Essentials are already installed if you are operating a Tanzu Kubernetes Grid or Tanzu Community Edition cluster.
For other Kubernetes providers, follow the steps below:
```
./install-cluster-essentials.sh
sudo install tanzu-cluster-essentials/kapp /usr/local/bin/kapp 
```

## Intall Tanzu CLI
[Documentation](https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-install-general.html#install-or-update-the-tanzu-cli-and-plugins-7)
### Clean install
```
./install-cli.sh
```
### Update Tanzu CLI 
[Documentation](https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-install-general.html#instructions-for-updating-tanzu-cli-that-was-installed-for-a-previous-release-of-tanzu-application-platform-10)
If the the instructions doesn't work and the `tanzu version` output is not as expected(v0.10.0), you can delete the wrong CLI version 
with the following commands and do a clean install.
```
sudo rm /usr/local/bin/tanzu
## Remove config directories
rm -rf ~/.config/tanzu/   # current location
rm -rf ~/.tanzu/          # old location
## Remove plugins on macOS
rm -rf ~/Library/Application\ Support/tanzu-cli/*
## Remove plugins on Linux
rm -rf ~/.local/share/tanzu-cli/*
```
## Install TAP Full profile
[Documentation](https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-install.html)

Copy values-example.yaml to values.yaml and set configuration values
```
cp values-example.yaml values.yaml
```

Run the installation script.
```
./install.sh
```

### Tips
- If you want to have https instead of http in the output of the application url with e.g. `tanzu apps workload get tanzu-java-web-app -n $DEVELOPER_NAMESPACE`, you can se the `default-external-scheme` configuration to `https` in the following CNR configuration:
    ```
    kubectl edit configmap config-network --namespace knative-serving
    ```
- You can update installation on updates in your values.yaml via 
    ```
    ytt -f tap-values.yaml -f values.yaml --ignore-unknown-comments > generated/tap-values.yaml
    tanzu package installed update tap --package-name tap.tanzu.vmware.com --version 1.0.0 --values-file generated/tap-values.yaml -n tap-install
    ```
- You can get a list of all the installed TAP packages via `tanzu package installed list -n tap-install` or `kubectl get PackageInstall -n tap-install` and have closer look at one of the installed packages via `kubectl describe PackageInstall <package-name> -n tap-install`
- You 

## Usage
[Documentation](https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-getting-started.html)

Save the configured developer namespace to an env variable via
```
DEVELOPER_NAMESPACE=$(cat values.yaml  | grep developer_namespace | awk '/developer_namespace:/ {print $2}')
```

Create a Tekton CI pipline that runs the unit-tests via
```
kubectl apply -f demo/tekton-pipeline.yaml -n $DEVELOPER_NAMESPACE
```

Create a scan policy via
```
kubectl apply -f demo/scan-policy.yaml -n $DEVELOPER_NAMESPACE
```

Create a workload via
```
tanzu apps workload create tanzu-java-web-app -n $DEVELOPER_NAMESPACE \
--git-repo https://github.com/tsalm-pivotal/tap-tanzu-java-web-app \
--git-branch main \
--type web \
--label apps.tanzu.vmware.com/has-tests=true \
--label app.kubernetes.io/part-of=tanzu-java-web-app \
--yes
```

Have a look at the logs and created resources via the following commands
```
tanzu apps workload tail tanzu-java-web-app -n $DEVELOPER_NAMESPACE --since 10m --timestamp
kubectl get workload,gitrepository,sourcescan,pipelinerun,images.kpack,imagescan,podintent,app,services.serving -n $DEVELOPER_NAMESPACE
tanzu apps workload get tanzu-java-web-app -n $DEVELOPER_NAMESPACE
```

### Tips
- [kubectl tree](https://github.com/ahmetb/kubectl-tree) is great [krew](https://krew.sigs.k8s.io) plugin to explore ownership relationships between Kubernetes objects. Here is an example for the created Workload:
```
kubectl tree workload tanzu-java-web-app -n $DEVELOPER_NAMESPACE
```

### Query for vulnerabilities
[Documentation](https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-scst-store-query_data.html)
Run the following command
```
kubectl describe imagescans tanzu-java-web-app -n $DEVELOPER_NAMESPACE
```
or query the metrics store with the insight CLI. [Documentation](https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-scst-store-query_data.html)
```
export METADATA_STORE_ACCESS_TOKEN=$(kubectl get secrets -n metadata-store -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='metadata-store-read-write-client')].data.token}" | base64 -d)
export INGRESS_DOMAIN=$(cat values.yaml | grep ingress -A 3 | awk '/domain:/ {print $2}')

insight config set-target https://metadata-store.${INGRESS_DOMAIN} --access-token=$METADATA_STORE_ACCESS_TOKEN --ca-cert
EXAMPLE_DIGEST=$(kubectl get kservice tanzu-java-web-app -n $DEVELOPER_NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}' | awk -F @ '{ print $2 }')
insight image get --digest $EXAMPLE_DIGEST --format json
insight image packages --digest $EXAMPLE_DIGEST --format json
insight image vulnerabilities --digest $EXAMPLE_DIGEST --format json
```
