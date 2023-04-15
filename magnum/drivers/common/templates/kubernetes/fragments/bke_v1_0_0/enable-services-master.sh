. /etc/sysconfig/heat-params

# make sure we pick up any modified unit files
systemctl daemon-reload

# if the certificate manager api is enabled, wait for the ca key to be handled
# by the heat container agent (required for the controller-manager)
while [ ! -f /etc/kubernetes/certs/ca.key ] && \
    [ "$(echo $CERT_MANAGER_API | tr '[:upper:]' '[:lower:]')" == "true" ]; do
    echo "waiting for CA to be made available for certificate manager api"
    sleep 2
done

echo "starting services"

container_runtime_service="containerd"

for action in enable restart; do
    for service in ${container_runtime_service} etcd kube-apiserver kube-controller-manager kube-scheduler kubelet kube-proxy; do
        echo "$action service $service"
        systemctl $action $service
    done
done

# Label self as master
until  [ "ok" = "$(kubectl get --raw='/healthz')" ] && \
    kubectl patch node ${INSTANCE_NAME} \
        --patch '{"metadata": {"labels": {"node-role.kubernetes.io/master": ""}}}'
do
    echo "Trying to label master node with node-role.kubernetes.io/master=\"\""
    sleep 5s
done
