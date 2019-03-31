#!/bin/sh

. /etc/sysconfig/heat-params

echo "Waiting for Kubernetes API..."
until  [ "ok" = "$(curl --silent http://127.0.0.1:8080/healthz)" ]
do
    sleep 5
done

if [ "$NETWORK_DRIVER" = "flannel" ]; then
  wget -O /tmp/kube-flannel.yml https://raw.githubusercontent.com/coreos/flannel/bc79dd1505b0c8681ece4de4c0d86c5cd2643275/Documentation/kube-flannel.yml
  sed -i "s@10.244.0.0/16@${PODS_NETWORK_CIDR}@g" /tmp/kube-flannel.yml
  kubectl apply -f /tmp/kube-flannel.yml 
fi

if [ "$NETWORK_DRIVER" = "calico" ]; then
  wget -O /tmp/rbac-kdd.yaml https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/hosted/rbac-kdd.yaml
  wget -O /tmp/calico.yaml https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/hosted/kubernetes-datastore/calico-networking/1.7/calico.yaml
  sed -i "s@192.168.0.0/16@${CALICO_IPV4POOL}@g" /tmp/calico.yaml
  sed -i "s@Always@Never@g" /tmp/calico.yaml
  kubectl apply -f /tmp/rbac-kdd.yaml 
  kubectl apply -f /tmp/calico.yaml 
fi
