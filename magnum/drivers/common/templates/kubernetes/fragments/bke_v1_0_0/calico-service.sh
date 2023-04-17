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
    if ! (kubectl get ns | grep tigera-operator); then
      kubectl create -f ${CALICO_TIGERA_MANIFEST_URL}
    else
      kubectl replace -f ${CALICO_TIGERA_MANIFEST_URL}
    fi

    cat <<EOF | kubectl apply -f -
---
# This section includes base Calico installation configuration.
# For more information, see: https://projectcalico.docs.tigera.io/master/reference/installation/api#operator.tigera.io/v1.Installation
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  # Configures Calico networking.
  calicoNetwork:
    # Note: The ipPools section cannot be modified post-install.
    ipPools:
    - blockSize: 26
      cidr: ${CALICO_IPV4POOL}
      encapsulation: None
      natOutgoing: Enabled
      nodeSelector: all()
---
# This section configures the Calico API server.
# For more information, see: https://projectcalico.docs.tigera.io/master/reference/installation/api#operator.tigera.io/v1.APIServer
apiVersion: operator.tigera.io/v1
kind: APIServer 
metadata: 
  name: default 
spec: {}
EOF
fi

printf "Finished running ${step}\n"
