step="install-clients"
printf "Starting to run ${step}\n"

set -e
set +x
. /etc/sysconfig/heat-params
set -x

mkdir -p /usr/local/bin/

curl -sSL "https://dl.k8s.io/${KUBE_TAG}/kubernetes-client-linux-amd64.tar.gz" | tar xzfv - -O kubernetes/client/bin/kubectl > /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

echo "INFO Installed kubectl."

printf "Finished running ${step}\n"
