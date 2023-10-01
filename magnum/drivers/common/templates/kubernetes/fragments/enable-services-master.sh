. /etc/sysconfig/heat-params

ssh_cmd="ssh -F /srv/magnum/.ssh/config root@localhost"

# make sure we pick up any modified unit files
$ssh_cmd systemctl daemon-reload

# if the certificate manager api is enabled, wait for the ca key to be handled
# by the heat container agent (required for the controller-manager)
while [ ! -f /etc/kubernetes/certs/ca.key ] && \
    [ "$(echo $CERT_MANAGER_API | tr '[:upper:]' '[:lower:]')" == "true" ]; do
    echo "waiting for CA to be made available for certificate manager api"
    sleep 2
done

echo "starting services"
if [ ${CONTAINER_RUNTIME} = "containerd"  ] ; then
    container_runtime_service="containerd"
else
    container_runtime_service="docker"
fi

for action in enable restart; do
    for service in ${container_runtime_service}; do
        echo "$action service $service"
        $ssh_cmd systemctl $action $service
    done
done

for action in enable restart; do
    for service in etcd; do
        echo "$action service $service"
        $ssh_cmd systemctl $action $service
    done
done

retry_remain=5
until [ "true" = "$(curl -s http://localhost:2379/health | jq -r '.health')" ] && \
    echo "etcd is healthy."
do
    if [ ${retry_remain} -ne 0 ] ; then
        echo "etcd is unhealthy. wait 5 seconds"
        sleep 5s
        retry_remain=$((${retry_remain}-1))
    else
        echo "etcd is unhealthy. give up..."\
        exit 1
    fi
done

for action in enable restart; do
    for service in kube-apiserver kube-controller-manager kube-scheduler kubelet kube-proxy; do
        echo "$action service $service"
        $ssh_cmd systemctl $action $service
    done
done

# Label self as master
until [ "ok" = "$(kubectl get --raw='/healthz')" ] && \
    kubectl patch node ${INSTANCE_NAME} \
        --patch '{"metadata": {"labels": {"node-role.kubernetes.io/master": ""}}}'
do
    echo "Trying to label master node with node-role.kubernetes.io/master=\"\""
    sleep 5s
done

if [ "$(echo $USE_PODMAN | tr '[:upper:]' '[:lower:]')" == "true" ]; then
    KUBE_DIGEST=$($ssh_cmd podman image inspect ${CONTAINER_INFRA_PREFIX:-${HYPERKUBE_PREFIX}}hyperkube:${KUBE_TAG} --format "{{.Digest}}")
    if [ -n "${KUBE_IMAGE_DIGEST}"  ] && [ "${KUBE_IMAGE_DIGEST}" != "${KUBE_DIGEST}" ]; then
        printf "The sha256 ${KUBE_DIGEST} of current hyperkube image cannot match the given one: ${KUBE_IMAGE_DIGEST}."
        exit 1
    fi
fi
