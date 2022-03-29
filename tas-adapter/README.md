# Unofficial Application Service Adapter for VMware Tanzu Application Platform (0.4.0)

It's always recommended to go through the official documentation in addition to this guide!
The scripts and commands in this guide were executed on a Amazon Linux 2 jumpbox. It's recommended to go through them step by step!

## Resources
 - [Public beta announcement](https://tanzu.vmware.com/content/blog/application-service-adapter-for-vmware-tanzu-application-platform-2)
 - [0.4.0 documentation](https://docs.vmware.com/en/Application-Service-Adapter-for-VMware-Tanzu-Application-Platform/0.4/tas-adapter/GUID-overview.html)

## Prerequisities
- You have to create the following private projects in Harbor `tas-adapter-droplets`, `tas-adapter-packages`. For other registries you may have to change the format of the `kpack_image_tag_prefix` and `package_registry_base_path` configuration values in `tas-adapter-values.yaml`
- Verify that you have installed the CF CLI version >=8 via `cf version`. See inscructions for the installation [here](https://github.com/cloudfoundry/cli/wiki/V8-CLI-Installation-Guide)

## Installation
Copy values-example.yaml to values.yaml and set configuration values
```
cp values-example.yaml values.yaml
```

Run the installation script.
```
./install.sh
```

## Known Issues / workarounds
- If you further have to increase the app memory allocation and don't want to override the default values, you can run `cf scale APP-NAME -m 2G` after a `cf push APP-NAME`

## Usage
```
export INGRESS_DOMAIN=$(cat values.yaml | grep ingress -A 3 | awk '/domain:/ {print $2}')
cf api api-tas-adapter.${INGRESS_DOMAIN}
cf login
cf create-org my-org
cf target -o "my-org"
cf create-space my-space
cf target -o "my-org" -s "my-space"
kubectl hns tree cf # Shows the hierarchy of the namespaces created for the org and space

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

See the documentation for all supported CF CLI commands [here](https://docs.vmware.com/en/Application-Service-Adapter-for-VMware-Tanzu-Application-Platform/0.4/tas-adapter/GUID-supported-cf-cli-commands.html)
