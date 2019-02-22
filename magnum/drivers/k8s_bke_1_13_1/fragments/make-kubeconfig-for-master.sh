#!/bin/sh

. /etc/sysconfig/heat-params

cert_dir=/etc/kubernetes/certs
CA_CERT=$cert_dir/ca.crt
config_dir=/etc/kubernetes

# create kubeconfig for kube-controller-manager
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=${CA_CERT} \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=${config_dir}/controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=${cert_dir}/controller-manager.crt \
  --client-key=${cert_dir}/controller-manager.key \
  --embed-certs=true \
  --kubeconfig=${config_dir}/controller-manager.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-controller-manager \
  --kubeconfig=${config_dir}/controller-manager.kubeconfig

kubectl config use-context default --kubeconfig=${config_dir}/controller-manager.kubeconfig

# create kubeconfig for kube-scheduler
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=${CA_CERT} \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=${config_dir}/scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=${cert_dir}/scheduler.crt \
  --client-key=${cert_dir}/scheduler.key \
  --embed-certs=true \
  --kubeconfig=${config_dir}/scheduler.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-scheduler \
  --kubeconfig=${config_dir}/scheduler.kubeconfig

kubectl config use-context default --kubeconfig=${config_dir}/scheduler.kubeconfig

# create kubeconfig for admin
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=${CA_CERT} \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=${config_dir}/admin.kubeconfig

kubectl config set-credentials admin \
  --client-certificate=${cert_dir}/admin.crt \
  --client-key=${cert_dir}/admin.key \
  --embed-certs=true \
  --kubeconfig=${config_dir}/admin.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=admin \
  --kubeconfig=${config_dir}/admin.kubeconfig

kubectl config use-context default --kubeconfig=${config_dir}/admin.kubeconfig
