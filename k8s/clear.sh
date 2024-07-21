#!/bin/bash
minikube kubectl -- delete --all sts
minikube kubectl -- delete --all pvc
minikube kubectl -- delete --all pv
minikube kubectl -- delete --all pod
rm -rf volume/*


