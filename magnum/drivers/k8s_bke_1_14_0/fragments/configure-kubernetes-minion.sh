#!/bin/sh -x

. /etc/sysconfig/heat-params

echo "configuring kubernetes (minion)"

CERT_DIR=/etc/kubernetes/certs
CONFIG_DIR=/etc/kubernetes
YAML_CONFIG_DIR=/etc/kubernetes/config
HOSTNAME_OVERRIDE=$(hostname --short | sed 's/\.novalocal//')
KUBE_PROTOCOL="https"
if [ "$TLS_DISABLED" = "True" ]; then
    KUBE_PROTOCOL="http"
fi
if [ "$(echo "${IS_MASTER}" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
    KUBE_MASTER_IP="127.0.0.1"
fi
KUBE_MASTER_URI="$KUBE_PROTOCOL://$KUBE_MASTER_IP:$KUBE_API_PORT"
mkdir -p ${YAML_CONFIG_DIR}

if [ "$(echo $CLOUD_PROVIDER_ENABLED | tr '[:upper:]' '[:lower:]')" = "true" ]; then
    CLOUD_CONTROLLER_OPTIONS="--cloud-provider=external"
fi

# install os dependency packages
yum -y install socat conntrack ipset

# install worker component binary
wget -O /tmp/cni-plugins-amd64-v0.7.5.tgz "https://github.com/containernetworking/plugins/releases/download/v0.7.5/cni-plugins-amd64-v0.7.5.tgz"
wget -O /tmp/crictl-v1.14.0-linux-amd64.tar.gz "https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.14.0/crictl-v1.14.0-linux-amd64.tar.gz"
wget -O /tmp/kubelet "https://storage.googleapis.com/kubernetes-release/release/${KUBE_VERSION}/bin/linux/amd64/kubelet"
wget -O /tmp/kube-proxy "https://storage.googleapis.com/kubernetes-release/release/${KUBE_VERSION}/bin/linux/amd64/kube-proxy"

chmod +x /tmp/{kubelet,kube-proxy}
mv /tmp/{kubelet,kube-proxy} /usr/local/bin/
mkdir -p /etc/cni/net.d \
         /opt/cni/bin
tar -xvf /tmp/crictl-v1.14.0-linux-amd64.tar.gz -C /usr/local/bin/
tar -xvf /tmp/cni-plugins-amd64-v0.7.5.tgz -C /opt/cni/bin/

# configure CNI loopback
cat <<EOF | sudo tee /etc/cni/net.d/99-loopback.conf
{
    "cniVersion": "0.3.1",
    "type": "loopback"
}
EOF

# configure kubelet
cat <<EOF | sudo tee ${YAML_CONFIG_DIR}/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "${CERT_DIR}/ca.crt"
authorization:
  mode: Webhook
clusterDomain: "${DNS_CLUSTER_DOMAIN}"
clusterDNS:
  - "${DNS_SERVICE_IP}"
resolvConf: "/etc/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "${CERT_DIR}/kubelet.crt"
tlsPrivateKeyFile: "${CERT_DIR}/kubelet.key"
EOF

cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=${YAML_CONFIG_DIR}/kubelet-config.yaml \\
  --container-runtime=docker \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=${CONFIG_DIR}/kubelet.kubeconfig \\
  --network-plugin=cni \\
  --register-node=true \\
  --hostname-override=${HOSTNAME_OVERRIDE} \\
  --read-only-port=10255 \\
  --v=2 ${CLOUD_CONTROLLER_OPTIONS}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# configure kube-proxy
cat <<EOF | sudo tee ${YAML_CONFIG_DIR}/proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "${CONFIG_DIR}/proxy.kubeconfig"
mode: "iptables"
clusterCIDR: "${PODS_NETWORK_CIDR}"
EOF

cat <<EOF | sudo tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=${YAML_CONFIG_DIR}/proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# wait for API server being started
until  [ "ok" = "$(curl --silent --cacert ${CERT_DIR}/ca.crt ${KUBE_MASTER_URI}/healthz)" ]
do
    echo "Waiting for Kubernetes API..."
    sleep 5
done

# enable and start kubelet
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

# enable and start kube-proxy
systemctl daemon-reload
systemctl enable kube-proxy
systemctl start kube-proxy

if [ "$(echo "${IS_MASTER}" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
  until [ "node/${HOSTNAME_OVERRIDE}" = "$(kubectl get node ${HOSTNAME_OVERRIDE} -o name)" ]
  do
      echo "Waiting for ${HOSTNAME_OVERRIDE} being registerd"
      sleep 3
  done
  kubectl label nodes ${HOSTNAME_OVERRIDE} node-role.kubernetes.io/master=""
  kubectl taint nodes ${HOSTNAME_OVERRIDE} node-role.kubernetes.io/master=:NoSchedule
fi
