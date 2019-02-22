#!/bin/sh

. /etc/sysconfig/heat-params

HOSTNAME_OVERRIDE=$(hostname --short | sed 's/\.novalocal//')
cert_dir=/etc/kubernetes/certs
CA_CERT=$cert_dir/ca.crt
config_dir=/etc/kubernetes
PROTOCOL=https
KUBE_PROTOCOL="https"
KUBELET_KUBECONFIG=${config_dir}/kubelet.kubeconfig
PROXY_KUBECONFIG=${config_dir}/proxy.kubeconfig

if [ "$TLS_DISABLED" = "True" ]; then
    PROTOCOL=http
    KUBE_PROTOCOL="http"
fi
if [ "$KUBE_MASTER_IP" = "" ]; then
    KUBE_MASTER_IP="127.0.0.1"
fi
KUBE_MASTER_URI="$KUBE_PROTOCOL://$KUBE_MASTER_IP:$KUBE_API_PORT"

# create kubeconfig for kubelet
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=${CA_CERT} \
  --embed-certs=true \
  --server=${KUBE_MASTER_URI} \
  --kubeconfig=${KUBELET_KUBECONFIG}

kubectl config set-credentials system:node:${HOSTNAME_OVERRIDE} \
  --client-certificate=${cert_dir}/kubelet.crt \
  --client-key=${cert_dir}/kubelet.key \
  --embed-certs=true \
  --kubeconfig=${KUBELET_KUBECONFIG}

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:node:${HOSTNAME_OVERRIDE} \
  --kubeconfig=${KUBELET_KUBECONFIG}

kubectl config use-context default --kubeconfig=${KUBELET_KUBECONFIG}

# create kubeconfig for kube-proxy
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=${CA_CERT} \
  --embed-certs=true \
  --server=${KUBE_MASTER_URI} \
  --kubeconfig=${PROXY_KUBECONFIG}

kubectl config set-credentials system:kube-proxy \
  --client-certificate=${cert_dir}/proxy.crt \
  --client-key=${cert_dir}/proxy.key \
  --embed-certs=true \
  --kubeconfig=${PROXY_KUBECONFIG}

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-proxy \
  --kubeconfig=${PROXY_KUBECONFIG}

kubectl config use-context default --kubeconfig=${PROXY_KUBECONFIG}
