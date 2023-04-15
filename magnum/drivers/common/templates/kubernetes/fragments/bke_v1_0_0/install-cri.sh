set +x

echo "START: install cri"

. /etc/sysconfig/heat-params
set -x

if [ -z "${CONTAINERD_TARBALL_URL}"  ] ; then
    CONTAINERD_TARBALL_URL="https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/cri-containerd-cni-${CONTAINERD_VERSION}-linux-amd64.tar.gz"
fi
i=0
until curl -o /tmp/cri-containerd.tar.gz -L "${CONTAINERD_TARBALL_URL}"
do
    i=$((i + 1))
    [ $i -lt 5 ] || break;
    sleep 5
done

if ! echo "${CONTAINERD_TARBALL_SHA256} /tmp/cri-containerd.tar.gz" | sha256sum -c - ; then
    echo "ERROR cri-containerd.tar.gz computed checksum did NOT match, exiting."
    exit 1
fi
tar xzvf /tmp/cri-containerd.tar.gz -C / --no-same-owner --touch --no-same-permissions

curl -o /lib/systemd/system/containerd.service https://raw.githubusercontent.com/containerd/containerd/main/containerd.service

systemctl daemon-reload
systemctl enable containerd
systemctl start containerd

wget -O /tmp/nerdctl-linux-amd64.tar.gz https://github.com/containerd/nerdctl/releases/download/v1.3.1/nerdctl-1.3.1-linux-amd64.tar.gz
wget -O /tmp/nerdctl-linux-amd64.sha256 https://github.com/containerd/nerdctl/releases/download/v1.3.1/SHA256SUMS
NERDCTL_TARBALL_SHA256=$(grep -e linux-amd64 /tmp/nerdctl-linux-amd64.sha256 | grep -v full | awk '{ print $1 }')
if ! echo "${NERDCTL_TARBALL_SHA256} /tmp/nerdctl-linux-amd64.tar.gz" | sha256sum -c - ; then
    echo "ERROR nerdctl-linux-amd64.tar.gz computed checksum did NOT match, exiting."
    exit 1
fi
tar xvfz /tmp/nerdctl-linux-amd64.tar.gz -C /usr/local/bin

echo "END: install cri"
