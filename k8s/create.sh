#!/bin/sh
minikube kubectl -- apply -f ./volume.yaml
minikube kubectl -- apply -f ./etcd.yaml
minikube kubectl -- apply -f ./db.yaml
minikube kubectl -- apply -f ./dev.yaml
