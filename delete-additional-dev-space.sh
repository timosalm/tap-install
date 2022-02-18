#!/bin/bash

if [ -z "$1" ]
  then
    echo "No argument for the developer namespace supplied"
    exit 1
fi

kubectl delete packageinstalls ${1}-grype -n tap-install
kubectl delete secret ${1}-grype-values -n tap-install
kubectl delete ns $1
