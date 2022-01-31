# Unofficial TAP 1.0 installation guide 

This installation guide should help you to install TAP 1.0 with wildcard certificates and [external-dns](https://github.com/kubernetes-sigs/external-dns) to a Kubernetes cluster.

It's always recommended to go through the official documentation in addition to this guide!
The scripts and commands in this guide were executed on an Amazon Linux 2 jumpbox. It's recommended to go through them step by step!

To also install the [Application Service Adapter for VMware Tanzu Application Platform public beta](https://tanzu.vmware.com/content/blog/application-service-adapter-for-vmware-tanzu-application-platform-2), you can follow the instructions [here](tas-adapter) after the installation of TAP.

## Resources
 - [1.0 documentation](https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-overview.html)

## Prerequisites 
[Pivnet CLI](https://github.com/pivotal-cf/pivnet-cli#installing)
- You have to create the following private projects in Harbor `tap`, `tap-wkld`. For other registries you may have to change the format of the `kp_default_repository` and `ootb_supply_chain_testing_scanning.registry.repository` configuration values in `tap-values.yaml` 
- A domain (configured in Route53)

## Provision a Kubernetes cluster

The scripts are currently only validated with GKE and AWS EKS, and Azure AKS!

### GKE

It looks like there is an [issue](https://jira.eng.vmware.com/browse/TANZUSC-821) with GKE during the installation where the cluster is overloaded even if there are enough resources available and it goes several times into a repair state / requests to the Kubernetes API timeout. You just have to wait for some time until every sub-package is in `ReconcileSucceeded` state.

With the following commands, you can provision a cluster with the [gcloud CLI](https://cloud.google.com/sdk/docs/install).
```
CLUSTER_ZONE=europe-west3-a
gcloud beta container clusters create tap --zone $CLUSTER_ZONE --cluster-version "1.21.5-gke.1302" --machine-type "e2-standard-4" --num-nodes "4" --node-locations $CLUSTER_ZONE --enable-pod-security-policy
gcloud container clusters get-credentials tap --zone $CLUSTER_ZONE
```
Configure Pod Security Policies so that Tanzu Application Platform controller pods can run as root.
```
kubectl create clusterrolebinding tap-psp-rolebinding --group=system:authenticated --clusterrole=gce:podsecuritypolicy:privileged
```

### AWS EKS
With the following commands, you can provision a cluster with the [aws CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
```
aws configure
export CLUSTER_NAME=tap-demo

# Create EKS cluster role
export CLUSTER_SERVICE_ROLE=$(aws iam create-role --role-name "${CLUSTER_NAME}-eks-role" --assume-role-policy-document='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"eks.amazonaws.com"},"Action": "sts:AssumeRole"}]}' --output text --query 'Role.Arn')
aws iam attach-role-policy --role-name "${CLUSTER_NAME}-eks-role" --policy-arn arn:aws:iam::aws:policy/AmazonEKSServicePolicy
aws iam attach-role-policy --role-name "${CLUSTER_NAME}-eks-role" --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# Create VPC
export STACK_ID=$(aws cloudformation create-stack --stack-name ${CLUSTER_NAME} --template-url https://amazon-eks.s3.us-west-2.amazonaws.com/cloudformation/2020-10-29/amazon-eks-vpc-private-subnets.yaml --output text --query 'StackId')
aws cloudformation wait stack-create-complete --stack-name ${CLUSTER_NAME}
export SECURITY_GROUP=$(aws cloudformation describe-stacks --stack-name ${CLUSTER_NAME} --query "Stacks[0].Outputs[?OutputKey=='SecurityGroups'].OutputValue" --output text)
export SUBNET_IDS=$(aws cloudformation describe-stacks --stack-name ${CLUSTER_NAME} --query "Stacks[0].Outputs[?OutputKey=='SubnetIds'].OutputValue" --output text)

# Create EKS cluster
aws eks create-cluster --name ${CLUSTER_NAME} --kubernetes-version 1.21 --role-arn "${CLUSTER_SERVICE_ROLE}" --resources-vpc-config subnetIds="${SUBNET_IDS}",securityGroupIds="${SECURITY_GROUP}"
aws eks wait cluster-active --name ${CLUSTER_NAME}

# Create EKS worker node role
export WORKER_SERVICE_ROLE=$(aws iam create-role --role-name "${CLUSTER_NAME}-eks-worker-role" --assume-role-policy-document='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action": "sts:AssumeRole"}]}' --output text --query 'Role.Arn')
aws iam attach-role-policy --role-name "${CLUSTER_NAME}-eks-worker-role" --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-role-policy --role-name "${CLUSTER_NAME}-eks-worker-role" --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam attach-role-policy --role-name "${CLUSTER_NAME}-eks-worker-role" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

# Create EKS worker nodes
aws eks create-nodegroup --cluster-name ${CLUSTER_NAME} --kubernetes-version 1.21 --nodegroup-name "${CLUSTER_NAME}-node-group" --disk-size 500 --scaling-config minSize=4,maxSize=4,desiredSize=4 --subnets $(echo $SUBNET_IDS | sed 's/,/ /g') --instance-types t3a.xlarge --node-role ${WORKER_SERVICE_ROLE}
aws eks wait nodegroup-active --cluster-name ${CLUSTER_NAME} --nodegroup-name ${CLUSTER_NAME}-node-group

aws eks update-kubeconfig --name ${CLUSTER_NAME}
```

### AKS Azure
With the following commands, you can provision a cluster with the [az CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli).

```
export CLUSTER_NAME=tap-demo
az login
az group create --location germanywestcentral --name ${CLUSTER_NAME}

# Add pod security policies support preview (required for learningcenter)
az extension add --name aks-preview
az feature register --name PodSecurityPolicyPreview --namespace Microsoft.ContainerService
# Wait until the status is "Registered"
az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/PodSecurityPolicyPreview')].{Name:name,State:properties.state}"
az provider register --namespace Microsoft.ContainerService

az aks create --resource-group ${CLUSTER_NAME} --name ${CLUSTER_NAME} --node-count 4 --enable-addons monitoring --node-vm-size Standard_DS3_v2 --node-osdisk-size 500 --enable-pod-security-policy

az aks get-credentials --resource-group ${CLUSTER_NAME} --name ${CLUSTER_NAME}

kubectl create clusterrolebinding tap-psp-rolebinding --group=system:authenticated --clusterrole=psp:privileged
```

## Install Cluster Essentials for VMware Tanzu

[Documentation](https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-install-general.html#tanzu-cluster-essentials)

The Cluster Essentials are already installed if you are operating a Tanzu Kubernetes Grid or Tanzu Community Edition cluster.
For other Kubernetes providers, follow the steps below:
```
./install-cluster-essentials.sh
sudo install tanzu-cluster-essentials/kapp /usr/local/bin/kapp 
```

## Install Tanzu CLI
[Documentation](https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-install-general.html#install-or-update-the-tanzu-cli-and-plugins-7)
### Clean install
```
./install-cli.sh
```
### Update Tanzu CLI 
[Documentation](https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-install-general.html#instructions-for-updating-tanzu-cli-that-was-installed-for-a-previous-release-of-tanzu-application-platform-10)
If the instructions don't work and the `tanzu version` output is not as expected(v0.10.0), you can delete the wrong CLI version 
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
- If you want to have HTTPS instead of HTTP in the output of the application URL with e.g. `tanzu apps workload get tanzu-java-web-app -n $DEVELOPER_NAMESPACE`, you can see the `default-external-scheme` configuration to `https` in the following CNR configuration:
    ```
    kubectl edit configmap config-network --namespace knative-serving
    ```
- You can update installation on updates in your values.yaml via 
    ```
    ytt -f tap-values.yaml -f values.yaml --ignore-unknown-comments > generated/tap-values.yaml
    tanzu package installed update tap --package-name tap.tanzu.vmware.com --version 1.0.0 --values-file generated/tap-values.yaml -n tap-install
    ```
- You can get a list of all the installed TAP packages via `tanzu package installed list -n tap-install` or `kubectl get PackageInstall -n tap-install` and have closer look at one of the installed packages via `kubectl describe PackageInstall <package-name> -n tap-install`

## Usage
[Documentation](https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-getting-started.html)

Save the configured developer namespace to an env variable via
```
DEVELOPER_NAMESPACE=$(cat values.yaml  | grep developer_namespace | awk '/developer_namespace:/ {print $2}')
```

Create a Tekton CI pipeline that runs the unit-tests via
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
NAMESPACE  NAME                                                  READY    REASON               AGE
dev-space  Workload/tanzu-java-web-app                           True     Ready                5m51s
dev-space  ├─ConfigMap/tanzu-java-web-app                        -                             3m6s
dev-space  ├─Deliverable/tanzu-java-web-app                      Unknown  ConditionNotMet      5m43s
dev-space  │ ├─App/tanzu-java-web-app                            -                             2m34s
dev-space  │ └─ImageRepository/tanzu-java-web-app-delivery       True                          5m39s
dev-space  ├─GitRepository/tanzu-java-web-app                    True     GitOperationSucceed  5m47s
dev-space  ├─Image/tanzu-java-web-app                            True                          4m51s
dev-space  │ ├─Build/tanzu-java-web-app-build-1                  -                             4m51s
dev-space  │ │ └─Pod/tanzu-java-web-app-build-1-build-pod        False    PodCompleted         4m50s
dev-space  │ ├─PersistentVolumeClaim/tanzu-java-web-app-cache    -                             4m51s
dev-space  │ └─SourceResolver/tanzu-java-web-app-source          True                          4m51s
dev-space  ├─ImageScan/tanzu-java-web-app                        -                             3m46s
dev-space  │ └─Job/scan-tanzu-java-web-appzgfvv                  -                             3m46s
dev-space  │   └─Pod/scan-tanzu-java-web-appzgfvv-fjf4g          False    PodCompleted         3m46s
dev-space  ├─PodIntent/tanzu-java-web-app                        True                          3m10s
dev-space  ├─Runnable/tanzu-java-web-app                         True     Ready                5m43s
dev-space  │ └─PipelineRun/tanzu-java-web-app-kx2ff              -                             5m39s
dev-space  │   └─TaskRun/tanzu-java-web-app-kx2ff-test           -                             5m39s
dev-space  │     └─Pod/tanzu-java-web-app-kx2ff-test-pod         False    PodCompleted         5m39s
dev-space  ├─Runnable/tanzu-java-web-app-config-writer           True     Ready                3m6s
dev-space  │ └─TaskRun/tanzu-java-web-app-config-writer-7hfr6    -                             3m3s
dev-space  │   └─Pod/tanzu-java-web-app-config-writer-7hfr6-pod  False    PodCompleted         3m3s
dev-space  └─SourceScan/tanzu-java-web-app                       -                             5m7s
dev-space    └─Job/scan-tanzu-java-web-appmbg65                  -                             5m7s
dev-space      └─Pod/scan-tanzu-java-web-appmbg65-b8k9k          False    PodCompleted         5m7s
```
- If the `mvnw` executable in your workload's repository doesn't have executable permissions(`chmod +x mvnw`) the Tektok pipeline will fail with a `./mvnw: Permission denied` error. To fix this for all java Maven workloads, this is done in the `demo/tekton-pipeline.yaml`.

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

insight config set-target https://metadata-store.${INGRESS_DOMAIN} --access-token=$METADATA_STORE_ACCESS_TOKEN
EXAMPLE_DIGEST=$(kubectl get kservice tanzu-java-web-app -n $DEVELOPER_NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}' | awk -F @ '{ print $2 }')
insight image get --digest $EXAMPLE_DIGEST --format json
insight image packages --digest $EXAMPLE_DIGEST --format json
insight image vulnerabilities --digest $EXAMPLE_DIGEST --format json
```
