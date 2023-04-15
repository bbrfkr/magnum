set +x

echo "START: install cri"

. /etc/sysconfig/heat-params
set -x

# install containerd
wget -O /tmp/containerd-linux-amd64.tar.gz "https://github.com/containerd/containerd/releases/download/v1.7.0/containerd-1.7.0-linux-amd64.tar.gz"
wget -O /tmp/containerd-linux-amd64.sha256sum "https://github.com/containerd/containerd/releases/download/v1.7.0/containerd-1.7.0-linux-amd64.tar.gz.sha256sum"
CONTAINERD_TARBALL_SHA256=$(cat /tmp/containerd-linux-amd64.sha256sum | awk '{ print $1 }')
if ! echo "${CONTAINERD_TARBALL_SHA256} /tmp/containerd-linux-amd64.tar.gz" | sha256sum -c - ; then
    echo "ERROR containerd-linux-amd64.tar.gz computed checksum did NOT match, exiting."
    exit 1
fi
tar xzvf /tmp/containerd-linux-amd64.tar.gz -C /usr/local/ --no-same-owner --touch --no-same-permissions

# install runc
wget -O /tmp/runc.amd64 "https://github.com/opencontainers/runc/releases/download/v1.1.6/runc.amd64"
wget -O /tmp/runc.sha256sum "https://github.com/opencontainers/runc/releases/download/v1.1.6/runc.sha256sum"
RUNC_TARBALL_SHA256=$(grep amd64 /tmp/runc.sha256sum | awk '{ print $1 }')
if ! echo "${RUNC_TARBALL_SHA256} /tmp/runc.amd64" | sha256sum -c - ; then
    echo "ERROR runc.amd64 computed checksum did NOT match, exiting."
    exit 1
fi
install -m 755 /tmp/runc.amd64 /usr/local/sbin/runc

# install cni
wget -O /tmp/cni-plugins-linux-amd64.tar.gz "https://github.com/containernetworking/plugins/releases/download/v1.2.0/cni-plugins-linux-amd64-v1.2.0.tgz"
wget -O /tmp/cni-plugins-linux-amd64.sha256sum "https://github.com/containernetworking/plugins/releases/download/v1.2.0/cni-plugins-linux-amd64-v1.2.0.tgz.sha256"
CNI_TARBALL_SHA256=$(cat /tmp/cni-plugins-linux-amd64.sha256sum | awk '{ print $1 }')
if ! echo "${CNI_TARBALL_SHA256} /tmp/cni-plugins-linux-amd64.tar.gz" | sha256sum -c - ; then
    echo "ERROR cni-plugins-linux-amd64.tar.gz computed checksum did NOT match, exiting."
    exit 1
fi
mkdir -p /opt/cni/bin
tar xzvf /tmp/cni-plugins-linux-amd64.tar.gz -C /opt/cni/bin/ --no-same-owner --touch --no-same-permissions

# enable containerd
curl -o /lib/systemd/system/containerd.service https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
systemctl daemon-reload
systemctl enable containerd
systemctl start containerd

# nerdctl
wget -O /tmp/nerdctl-linux-amd64.tar.gz https://github.com/containerd/nerdctl/releases/download/v1.3.1/nerdctl-1.3.1-linux-amd64.tar.gz
wget -O /tmp/nerdctl-linux-amd64.sha256 https://github.com/containerd/nerdctl/releases/download/v1.3.1/SHA256SUMS
NERDCTL_TARBALL_SHA256=$(grep -e linux-amd64 /tmp/nerdctl-linux-amd64.sha256 | grep -v full | awk '{ print $1 }')
if ! echo "${NERDCTL_TARBALL_SHA256} /tmp/nerdctl-linux-amd64.tar.gz" | sha256sum -c - ; then
    echo "ERROR nerdctl-linux-amd64.tar.gz computed checksum did NOT match, exiting."
    exit 1
fi
tar xvfz /tmp/nerdctl-linux-amd64.tar.gz -C /usr/local/bin/

echo "END: install cri"
