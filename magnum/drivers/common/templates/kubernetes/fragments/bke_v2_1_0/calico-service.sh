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
    CALICO_TIGERA_MANIFEST_URL="https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/tigera-operator.yaml"
    if ! (kubectl get ns | grep tigera-operator); then
      kubectl create -f ${CALICO_TIGERA_MANIFEST_URL}
    else
      kubectl replace -f ${CALICO_TIGERA_MANIFEST_URL}
    fi

    cat <<EOF | kubectl apply -f -
---
# This section includes base Calico installation configuration.
# For more information, see: https://docs.tigera.io/calico/latest/reference/installation/api#operator.tigera.io/v1.Installation
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  # Configures Calico networking.
  calicoNetwork:
    ipPools:
      - name: default-ipv4-ippool
        blockSize: 26
        cidr: ${CALICO_IPV4POOL}
        encapsulation: VXLANCrossSubnet
        natOutgoing: Enabled
        nodeSelector: all()

---
# This section configures the Calico API server.
# For more information, see: https://docs.tigera.io/calico/latest/reference/installation/api#operator.tigera.io/v1.APIServer
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}

---
# Configures the Calico Goldmane flow aggregator.
apiVersion: operator.tigera.io/v1
kind: Goldmane
metadata:
  name: default

---
# Configures the Calico Whisker observability UI.
apiVersion: operator.tigera.io/v1
kind: Whisker
metadata:
  name: default
EOF
fi

printf "Finished running ${step}\n"
