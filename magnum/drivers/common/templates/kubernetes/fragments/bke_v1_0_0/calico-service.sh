step="calico-service"
printf "Starting to run ${step}\n"

set -e
set +x
. /etc/sysconfig/heat-params
set -x

if [ "$NETWORK_DRIVER" = "calico" ]; then
    until  [ "ok" = "$(kubectl get --raw='/healthz')" ]
    do
        echo "Waiting for Kubernetes API..."
        sleep 5
    done
    CALICO_TIGERA_MANIFEST_URL="https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/tigera-operator.yaml"
    CALICO_MANIFEST_URL="https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/custom-resources.yaml"
    wget -O /tmp/calico-custom-resources.yaml ${CALICO_MANIFEST_URL}
    sed -i "s@cidr: .*@cidr: ${CALICO_IPV4POOL}@g" /tmp/calico-custom-resources.yaml

    kubectl get ns | grep tigera-operator
    if [ $? -eq 0 ]; then
      kubectl replace -f ${CALICO_TIGERA_MANIFEST_URL}
    else
      kubectl create -f ${CALICO_TIGERA_MANIFEST_URL}
    fi
    kubectl apply -f /tmp/calico-custom-resources.yaml
fi

printf "Finished running ${step}\n"
