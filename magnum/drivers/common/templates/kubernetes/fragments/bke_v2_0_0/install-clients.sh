step="install-clients"
printf "Starting to run ${step}\n"

set -e
set +x
. /etc/sysconfig/heat-params
set -x

mkdir -p /usr/local/bin/

curl -o /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/${KUBE_TAG}/bin/linux/amd64/kubectl
chmod +x /usr/local/bin/kubectl

echo "INFO Installed kubectl."

printf "Finished running ${step}\n"
