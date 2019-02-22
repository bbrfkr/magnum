#!/bin/sh

. /etc/sysconfig/heat-params

echo "Waiting for Kubernetes API..."
until  [ "ok" = "$(curl --silent http://127.0.0.1:8080/healthz)" ]
do
    sleep 5
done

wget -O /tmp/coredns.yaml https://storage.googleapis.com/kubernetes-the-hard-way/coredns.yaml
sed -i "s/10.32.0.10/${DNS_SERVICE_IP}/g" /tmp/coredns.yaml
sed -i "s@coredns/coredns:.*@coredns/coredns:1.3.1@g" /tmp/coredns.yaml
kubectl apply -f /tmp/coredns.yaml
