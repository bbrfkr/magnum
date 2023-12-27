set -x

# make sure we pick up any modified unit files
systemctl daemon-reload

container_runtime_service="containerd"

for action in enable restart; do
    for service in ${container_runtime_service} kubelet kube-proxy; do
        echo "$action service $service"
        systemctl $action $service
    done
done
