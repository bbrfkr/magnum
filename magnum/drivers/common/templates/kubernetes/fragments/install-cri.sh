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

curl -o /usr/local/lib/systemd/system/containerd.service https://raw.githubusercontent.com/containerd/containerd/main/containerd.service

systemctl daemon-reload
systemctl enable containerd
systemctl start containerd

curl -o /tmp/runc.amd64 https://github.com/opencontainers/runc/releases/download/v1.1.6/runc.amd64
curl -o /tmp/runc.sha256sum https://github.com/opencontainers/runc/releases/download/v1.1.6/runc.sha256sum
RUNC_SHA256=$(cat /tmp/runc.sha256sum)
if ! echo "${RUNC_SHA256} /tmp/runc.amd64" | sha256sum -c - ; then
    echo "ERROR runc.amd64 computed checksum did NOT match, exiting."
    exit 1
fi
install -m 755 runc.amd64 /usr/local/sbin/runc

echo "END: install cri"
