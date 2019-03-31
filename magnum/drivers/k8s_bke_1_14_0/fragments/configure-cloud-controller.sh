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
          image: docker.io/k8scloudprovider/openstack-cloud-controller-manager:1.14.0
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
CLOUD_CONFIG=$(base64 -w 0 ${CONFIG_DIR}/cloud-config)
wget -O /tmp/csi-secret-cinderplugin.yaml "https://raw.githubusercontent.com/kubernetes/cloud-provider-openstack/release-1.13/manifests/cinder-csi-plugin/csi-secret-cinderplugin.yaml"
sed -i "s/cloud.conf: .*/cloud.conf: ${CLOUD_CONFIG}/g" /tmp/csi-secret-cinderplugin.yaml

kubectl apply -f /tmp/csi-secret-cinderplugin.yaml -n kube-system

add_parenthesis () {
  echo -n \$\($1\)
}
cat <<EOF > /tmp/csi-cinderplugin.yaml
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
---
kind: Service
apiVersion: v1
metadata:
  name: csi-attacher-cinderplugin
  labels:
    app: csi-attacher-cinderplugin
spec:
  selector:
    app: csi-attacher-cinderplugin
  ports:
    - name: dummy
      port: 12345
---
kind: StatefulSet
apiVersion: apps/v1beta1
metadata:
  name: csi-attacher-cinderplugin
spec:
  serviceName: "csi-attacher-cinderplugin"
  replicas: 1
  template:
    metadata:
      labels:
        app: csi-attacher-cinderplugin
    spec:
      nodeSelector:
        node-role.kubernetes.io/master: ""
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      serviceAccount: csi-attacher
      containers:
        - name: csi-attacher
          image: quay.io/k8scsi/csi-attacher:v1.0.1
          args:
            - "--v=5"
            - "--csi-address=$(add_parenthesis ADDRESS)"
          env:
            - name: ADDRESS
              value: /var/lib/csi/sockets/pluginproxy/csi.sock
          imagePullPolicy: "IfNotPresent"
          volumeMounts:
            - name: socket-dir
              mountPath: /var/lib/csi/sockets/pluginproxy/
        - name: cinder
          image: docker.io/k8scloudprovider/cinder-csi-plugin:v1.14.0
          args :
            - /bin/cinder-csi-plugin
            - "--nodeid=$(add_parenthesis NODE_ID)"
            - "--endpoint=$(add_parenthesis CSI_ENDPOINT)"
            - "--cloud-config=$(add_parenthesis CLOUD_CONFIG)"
          env:
            - name: NODE_ID
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: CSI_ENDPOINT
              value: unix://csi/csi.sock
            - name: CLOUD_CONFIG
              value: /etc/config/cloud.conf
          imagePullPolicy: "IfNotPresent"
          volumeMounts:
            - name: socket-dir
              mountPath: /csi
            - name: secret-cinderplugin
              mountPath: /etc/config
              readOnly: true
      volumes:
        - name: socket-dir
          emptyDir:
        - name: secret-cinderplugin
          secret:
            secretName: csi-secret-cinderplugin
---
kind: DaemonSet
apiVersion: apps/v1beta2
metadata:
  name: csi-nodeplugin-cinderplugin
spec:
  selector:
    matchLabels:
      app: csi-nodeplugin-cinderplugin
  template:
    metadata:
      labels:
        app: csi-nodeplugin-cinderplugin
    spec:
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      serviceAccount: csi-nodeplugin
      hostNetwork: true
      containers:
        - name: driver-registrar
          image: quay.io/k8scsi/driver-registrar:v1.0.1
          args:
            - "--v=5"
            - "--csi-address=$(add_parenthesis ADDRESS)"
            - "--kubelet-registration-path=$(add_parenthesis DRIVER_REG_SOCK_PATH)"
          env:
            - name: ADDRESS
              value: /csi/csi.sock
            - name: DRIVER_REG_SOCK_PATH
              value: /var/lib/kubelet/plugins/csi-cinderplugin/csi.sock
            - name: KUBE_NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
          imagePullPolicy: "IfNotPresent"
          volumeMounts:
            - name: socket-dir
              mountPath: /csi
            - name: registration-dir
              mountPath: /registration
        - name: cinder
          securityContext:
            privileged: true
            capabilities:
              add: ["SYS_ADMIN"]
            allowPrivilegeEscalation: true
          image: docker.io/k8scloudprovider/cinder-csi-plugin:v1.14.0
          args :
            - /bin/cinder-csi-plugin
            - "--nodeid=$(add_parenthesis NODE_ID)"
            - "--endpoint=$(add_parenthesis CSI_ENDPOINT)"
            - "--cloud-config=$(add_parenthesis CLOUD_CONFIG)"
          env:
            - name: NODE_ID
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: CSI_ENDPOINT
              value: unix://csi/csi.sock
            - name: CLOUD_CONFIG
              value: /etc/config/cloud.conf
          imagePullPolicy: "IfNotPresent"
          volumeMounts:
            - name: socket-dir
              mountPath: /csi
            - name: pods-mount-dir
              mountPath: /var/lib/kubelet/pods
              mountPropagation: "Bidirectional"
            - name: pods-cloud-data
              mountPath: /var/lib/cloud/data
              readOnly: true
            - name: pods-probe-dir
              mountPath: /dev
              mountPropagation: "HostToContainer"
            - name: secret-cinderplugin
              mountPath: /etc/config
              readOnly: true
      volumes:
        - name: socket-dir
          hostPath:
            path: /var/lib/kubelet/plugins/csi-cinderplugin
            type: DirectoryOrCreate
        - name: registration-dir
          hostPath:
            path: /var/lib/kubelet/plugins/
            type: Directory
        - name: pods-mount-dir
          hostPath:
            path: /var/lib/kubelet/pods
            type: Directory
        - name: pods-cloud-data
          hostPath:
            path: /var/lib/cloud/data
            type: Directory
        - name: pods-probe-dir
          hostPath:
            path: /dev
            type: Directory
        - name: secret-cinderplugin
          secret:
            secretName: csi-secret-cinderplugin
---
kind: Service
apiVersion: v1
metadata:
  name: csi-provisioner-cinderplugin
  labels:
    app: csi-provisioner-cinderplugin
spec:
  selector:
    app: csi-provisioner-cinderplugin
  ports:
    - name: dummy
      port: 12345
---
kind: StatefulSet
apiVersion: apps/v1beta1
metadata:
  name: csi-provisioner-cinderplugin
spec:
  serviceName: "csi-provisioner-cinderplugin"
  replicas: 1
  template:
    metadata:
      labels:
        app: csi-provisioner-cinderplugin
    spec:
      nodeSelector:
        node-role.kubernetes.io/master: ""
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      serviceAccount: csi-provisioner
      containers:
        - name: csi-provisioner
          image: quay.io/k8scsi/csi-provisioner:v1.0.1
          args:
            - "--provisioner=csi-cinderplugin"
            - "--csi-address=$(add_parenthesis ADDRESS)"
          env:
            - name: ADDRESS
              value: /var/lib/csi/sockets/pluginproxy/csi.sock
          imagePullPolicy: "IfNotPresent"
          volumeMounts:
            - name: socket-dir
              mountPath: /var/lib/csi/sockets/pluginproxy/
        - name: cinder
          image: docker.io/k8scloudprovider/cinder-csi-plugin:v1.14.0
          args :
            - /bin/cinder-csi-plugin
            - "--nodeid=$(add_parenthesis NODE_ID)"
            - "--endpoint=$(add_parenthesis CSI_ENDPOINT)"
            - "--cloud-config=$(add_parenthesis CLOUD_CONFIG)"
          env:
            - name: NODE_ID
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: CSI_ENDPOINT
              value: unix://csi/csi.sock
            - name: CLOUD_CONFIG
              value: /etc/config/cloud.conf
          imagePullPolicy: "IfNotPresent"
          volumeMounts:
            - name: socket-dir
              mountPath: /csi
            - name: secret-cinderplugin
              mountPath: /etc/config
              readOnly: true
      volumes:
        - name: socket-dir
          emptyDir:
        - name: secret-cinderplugin
          secret:
            secretName: csi-secret-cinderplugin
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-cinder
  annotations:
    storageclass.beta.kubernetes.io/is-default-class: "true"
provisioner: csi-cinderplugin
EOF

kubectl apply -f /tmp/csi-cinderplugin.yaml -n kube-system
