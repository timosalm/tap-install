# Unofficial Application Service Adapter for VMware Tanzu Application Platform (0.2.0)

It's always recommended to go through the official documentation in addition to this guide!
The scripts and commands in this guide were executed on a Amazon Linux 2 jumpbox. It's recommended to go through them step by step!

## Resources
 - [Public beta announcement](https://tanzu.vmware.com/content/blog/application-service-adapter-for-vmware-tanzu-application-platform-2)
 - [0.2.0 documentation](https://docs.vmware.com/en/Application-Service-Adapter-for-VMware-Tanzu-Application-Platform/0.2/tas-adapter-0-2/GUID-overview.html)

## Things additionally handled in the installation script
- The 500M default app memory allocation is not sufficient for Java apps, and the app manifest does not yet accept the memory parameter to set it on push -> Set default to 1024M

## Prerequisities
- You have to create the following private projects in Harbor `tas-adapter-droplets`, `tas-adapter-packages`. For other registries you may have to change the format of the `kpack_image_tag_prefix` and `package_registry_base_path` configuration values in `tas-adapter-values.yaml` 

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
- If you have pushed an application with multiple processes, which is the case for most of e.g. the Spring Boot apps built by TBS, all commands related to apps fail with the following error:
	```
	Error unmarshalling the following into a cloud controller error: upstream connect error or disconnect/reset before headers. reset reason: connection termination
	```
	The workaround is to get all the processes via `curl /v3/processes | jq '.resources[] | {type, instances, relationships}'` and scale to 1 via `cf scale APP-NAME -i 1 --process PROCESS-TYPE`.
	For a typical Spring Boot app the workaround should be:
	```
	cf scale APP-NAME -i 1 --process executable-jar
	cf scale APP-NAME -i 1 --process task
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

git clone https://github.com/tsalm-pivotal/spring-boot-hello-world.git
cd spring-boot-hello-world
cf push hello-world

# See section "Known Issues / workarounds"
cf scale hello-world -i 1 --process executable-jar
cf scale hello-world -i 1 --process task

curl "https://hello-world.tas-adapter.${INGRESS_DOMAIN}"

cf apps
cf routes
cf orgs
cf spaces
```
