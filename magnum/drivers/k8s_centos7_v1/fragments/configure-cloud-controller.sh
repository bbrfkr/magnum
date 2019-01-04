#!/bin/sh

if [ "$(echo $CLOUD_PROVIDER_ENABLED | tr '[:upper:]' '[:lower:]')" != "true" ]; then
  exit 0
fi

kubectl create secret generic cloud-config \
  --from-file=/etc/kubernetes/cloud-config \
  -n kube-system

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-controller-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:cloud-node-controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: cloud-node-controller
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:pvl-controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: pvl-controller
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:cloud-controller-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: cloud-controller-manager
  namespace: kube-system
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: openstack-cloud-controller-manager
  namespace: kube-system
  labels:
    k8s-app: openstack-cloud-controller-manager
spec:
  selector:
    matchLabels:
      k8s-app: openstack-cloud-controller-manager
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        k8s-app: openstack-cloud-controller-manager
    spec:
      nodeSelector:
        node-role.kubernetes.io/master: ""
      securityContext:
        runAsUser: 1001
      tolerations:
      - key: node.cloudprovider.kubernetes.io/uninitialized
        value: "true"
        effect: NoSchedule
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      serviceAccountName: cloud-controller-manager
      containers:
        - name: openstack-cloud-controller-manager
          image: docker.io/k8scloudprovider/openstack-cloud-controller-manager:1.13.1
          args:
            - /bin/openstack-cloud-controller-manager
            - --v=1
            - --cloud-config=/etc/cloud/cloud-config
            - --cloud-provider=openstack
            - --use-service-account-credentials=true
            - --address=127.0.0.1
          volumeMounts:
            - mountPath: /etc/cloud
              name: cloud-config-volume
              readOnly: true
            - mountPath: /etc/kubernetes
              name: k8s-configs
              readOnly: true
          resources:
            requests:
              cpu: 200m
      hostNetwork: true
      volumes:
      - name: cloud-config-volume
        secret:
          secretName: cloud-config
      - hostPath:
          path: /etc/kubernetes
          type: DirectoryOrCreate
        name: k8s-configs
EOF

CONFIG_DIR=/etc/kubernetes

mkdir -p /tmp/csi-cinder-plugin
cd /tmp/csi-cinder-plugin
wget "https://raw.githubusercontent.com/kubernetes/cloud-provider-openstack/release-1.13/manifests/cinder-csi-plugin/csi-attacher-cinderplugin.yaml"
wget "https://raw.githubusercontent.com/kubernetes/cloud-provider-openstack/release-1.13/manifests/cinder-csi-plugin/csi-nodeplugin-cinderplugin.yaml"
wget "https://raw.githubusercontent.com/kubernetes/cloud-provider-openstack/release-1.13/manifests/cinder-csi-plugin/csi-provisioner-cinderplugin.yaml"
wget "https://raw.githubusercontent.com/kubernetes/cloud-provider-openstack/release-1.13/manifests/cinder-csi-plugin/csi-secret-cinderplugin.yaml"

CLOUD_CONFIG=$(base64 -w 0 ${CONFIG_DIR}/cloud-config)
sed -i "s/cloud.conf: .*/cloud.conf: ${CLOUD_CONFIG}/g" csi-secret-cinderplugin.yaml

cat <<EOF | kubectl apply -n kube-system -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: csi-attacher
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: csi-attacher-role
subjects:
  - kind: ServiceAccount
    name: csi-attacher
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: csi-nodeplugin
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: csi-nodeplugin
subjects:
  - kind: ServiceAccount
    name: csi-nodeplugin
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: csi-provisioner
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: csi-provisioner-role
subjects:
  - kind: ServiceAccount
    name: csi-provisioner
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f . -n kube-system

cat <<EOF | kubectl apply -n kube-system -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-cinderplugin
  annotations:
    storageclass.beta.kubernetes.io/is-default-class: "true"
provisioner: csi-cinderplugin
EOF
