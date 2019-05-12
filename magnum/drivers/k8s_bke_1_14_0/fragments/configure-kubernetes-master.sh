#!/bin/sh -x

. /etc/sysconfig/heat-params

echo "configuring kubernetes (master)"

CERT_DIR=/etc/kubernetes/certs
ETCD_CERT_DIR=/etc/etcd/certs
CONFIG_DIR=/etc/kubernetes
YAML_CONFIG_DIR=/etc/kubernetes/config

# install master component binary
wget -O /tmp/kube-apiserver "https://storage.googleapis.com/kubernetes-release/release/${KUBE_VERSION}/bin/linux/amd64/kube-apiserver"
wget -O /tmp/kube-controller-manager "https://storage.googleapis.com/kubernetes-release/release/${KUBE_VERSION}/bin/linux/amd64/kube-controller-manager"
wget -O /tmp/kube-scheduler "https://storage.googleapis.com/kubernetes-release/release/${KUBE_VERSION}/bin/linux/amd64/kube-scheduler"

chmod +x /tmp/{kube-apiserver,kube-controller-manager,kube-scheduler}
mv /tmp/{kube-apiserver,kube-controller-manager,kube-scheduler} /usr/local/bin/

if [ "$(echo $CLOUD_PROVIDER_ENABLED | tr '[:upper:]' '[:lower:]')" = "true" ]; then
  CLOUD_CONTROLLER_OPTIONS="--cloud-provider=external"
  CLOUD_CONTROLLER_OPTIONS_FOR_API="--cloud-provider=external --runtime-config=storage.k8s.io/v1alpha1=true"
fi

# create kube-apiserver config
INTERNAL_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
cat <<EOF | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${INTERNAL_IP} \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --secure-port=${KUBE_API_PORT} \\
  --client-ca-file=${CERT_DIR}/ca.crt \\
  --enable-admission-plugins=NodeRestriction,${ADMISSION_CONTROL_LIST} \\
  --enable-swagger-ui=true \\
  --etcd-cafile=${ETCD_CERT_DIR}/ca.crt \\
  --etcd-certfile=${ETCD_CERT_DIR}/kubernetes.crt \\
  --etcd-keyfile=${ETCD_CERT_DIR}/kubernetes.key \\
  --etcd-servers=http://127.0.0.1:2379 \\
  --event-ttl=1h \\
  --experimental-encryption-provider-config=${YAML_CONFIG_DIR}/encryption-config.yaml \\
  --kubelet-certificate-authority=${CERT_DIR}/ca.crt \\
  --kubelet-client-certificate=${CERT_DIR}/kubernetes.crt \\
  --kubelet-client-key=${CERT_DIR}/kubernetes.key \\
  --kubelet-https=true \\
  --runtime-config=api/all \\
  --service-account-key-file=${CERT_DIR}/service_account.key \\
  --service-cluster-ip-range=${PORTAL_NETWORK_CIDR} \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=${CERT_DIR}/kubernetes.crt \\
  --tls-private-key-file=${CERT_DIR}/kubernetes.key \\
  --requestheader-client-ca-file=${CERT_DIR}/ca.crt \\
  --requestheader-allowed-names=front-proxy-client \\
  --requestheader-extra-headers-prefix=X-Remote-Extra- \\
  --requestheader-group-headers=X-Remote-Group \\
  --requestheader-username-headers=X-Remote-User \\
  --proxy-client-cert-file=${CERT_DIR}/front-proxy.crt \\
  --proxy-client-key-file=${CERT_DIR}/front-proxy.key \\
  --v=2 ${CLOUD_CONTROLLER_OPTIONS_FOR_API}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# enable and start kube-apiserver service
systemctl daemon-reload
systemctl enable kube-apiserver
systemctl start kube-apiserver

# create kube-controller-manager config
if [ "$(echo $CERT_MANAGER_API | tr '[:upper:]' '[:lower:]')" = "true" ]; then
    CONTROLLER_MANAGER_SIGNING_OPTIONS="--cluster-signing-cert-file=${CERT_DIR}/ca.crt --cluster-signing-key-file=$CERT_DIR/ca.key"
fi
cat <<EOF | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=${PODS_NETWORK_CIDR} \\
  --cluster-name=kubernetes \\
  --kubeconfig=${CONFIG_DIR}/controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=${CERT_DIR}/ca.crt \\
  --service-account-private-key-file=${CERT_DIR}/service_account_private.key \\
  --service-cluster-ip-range=${PORTAL_NETWORK_CIDR} \\
  --use-service-account-credentials=true \\
  --allocate-node-cidrs=true \\
  --v=2 ${CONTROLLER_MANAGER_SIGNING_OPTIONS} ${CLOUD_CONTROLLER_OPTIONS}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# enable and start kube-controller-manager service
systemctl daemon-reload
systemctl enable kube-controller-manager
systemctl start kube-controller-manager

# create kube-scheduler config
cat <<EOF | sudo tee ${YAML_CONFIG_DIR}/kube-scheduler.yaml
apiVersion: kubescheduler.config.k8s.io/v1alpha1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "${CONFIG_DIR}/scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF

cat <<EOF | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=${YAML_CONFIG_DIR}/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# enable and start kube-scheduler service
systemctl daemon-reload
systemctl enable kube-scheduler
systemctl start kube-scheduler
