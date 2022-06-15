# Unofficial Application Service Adapter for VMware Tanzu Application Platform (0.8.0)

It's always recommended to go through the official documentation in addition to this guide!
The scripts and commands in this guide were executed on a Amazon Linux 2 jumpbox. It's recommended to go through them step by step!

## Resources
 - [Public beta announcement, Jan 2022](https://tanzu.vmware.com/content/blog/application-service-adapter-for-vmware-tanzu-application-platform-2)
 - [Update on betas, April 2022](https://tanzu.vmware.com/content/blog/application-service-adapter-for-vmware-tanzu-application-platform-beta)
 - [0.8.0 documentation](https://docs.vmware.com/en/Application-Service-Adapter-for-VMware-Tanzu-Application-Platform/0.8/tas-adapter/GUID-overview.html)

## Prerequisities
- You have to create the following private projects in Harbor `tas-adapter-droplets`, `tas-adapter-packages`. For other registries you may have to change the format of the `kpack_image_tag_prefix` and `package_registry_base_path` configuration values in `tas-adapter-values.yaml`
- Verify that you have installed the CF CLI version >=8 via `cf version`. See instructions for the installation [here](https://github.com/cloudfoundry/cli/wiki/V8-CLI-Installation-Guide)

## Installation
Copy values-example.yaml to values.yaml and set configuration values
```
cp values-example.yaml values.yaml
```

Run the installation script.
```
./install.sh
```

## Usage
```
export INGRESS_DOMAIN=$(cat values.yaml | grep ingress -A 3 | awk '/domain:/ {print $2}')
cf api api-tas-adapter.${INGRESS_DOMAIN}
cf login
cf create-org my-org
cf target -o "my-org"
cf create-space my-space
cf target -o "my-org" -s "my-space"

# see the CFOrg resources in the root CF namespace
kubectl get cforgs -n cf

# see the CFSpace resources across all the CF-org namespaces
kubectl get cfspaces -A

# see that the names of the underlying namespaces match
kubectl get namespaces | grep '^cf'


git clone https://github.com/tsalm-pivotal/spring-boot-hello-world.git
cd spring-boot-hello-world
cf push hello-world

curl "https://hello-world.tas-adapter.${INGRESS_DOMAIN}"

cf apps
cf routes
cf orgs
cf spaces
cf buildpacks
cf restage
cf delete-route
cf set-env 
cf create-user-provided-service
cf bind-service # for user provided services
cf delete-service # for user provided services
cf get-health-check
```

See the documentation for all supported CF CLI commands [here](https://docs.vmware.com/en/Application-Service-Adapter-for-VMware-Tanzu-Application-Platform/0.8/tas-adapter/GUID-supported-cf-cli-commands.html)
