step="install-clients"
printf "Starting to run ${step}\n"

set -e
set +x
. /etc/sysconfig/heat-params
set -x

mkdir -p /srv/magnum/bin/

curl -o /srv/magnum/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/${KUBE_TAG}/bin/linux/amd64/kubectl
chmod +x /srv/magnum/bin/kubectl

echo "INFO Installed kubectl."

echo "export PATH=/srv/magnum/bin:\$PATH" >> /etc/bashrc
export PATH=/srv/magnum/bin:$PATH

printf "Finished running ${step}\n"
