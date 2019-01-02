#!/bin/sh

. /etc/sysconfig/heat-params

set -x

# prepare etcd cinder volume
if [ -n "$ETCD_VOLUME_SIZE" ] && [ "$ETCD_VOLUME_SIZE" -gt 0 ]; then

    attempts=60
    while [ ${attempts} -gt 0 ]; do
        device_name=$(ls /dev/disk/by-id | grep ${ETCD_VOLUME:0:20}$)
        if [ -n "${device_name}" ]; then
            break
        fi
        echo "waiting for disk device"
        sleep 0.5
        udevadm trigger
        let attempts--
    done

    if [ -z "${device_name}" ]; then
        echo "ERROR: disk device does not exist" >&2
        exit 1
    fi

    device_path=/dev/disk/by-id/${device_name}
    fstype=$(blkid -s TYPE -o value ${device_path})
    if [ "${fstype}" != "xfs" ]; then
        mkfs.xfs -f ${device_path}
    fi
    mkdir -p /var/lib/etcd
    echo "${device_path} /var/lib/etcd xfs defaults 0 0" >> /etc/fstab
    mount -a
    chown -R etcd.etcd /var/lib/etcd
    chmod 755 /var/lib/etcd

fi

# install etcd binary
wget -O /tmp/etcd-${ETCD_TAG}-linux-amd64.tar.gz "https://github.com/coreos/etcd/releases/download/${ETCD_TAG}/etcd-${ETCD_TAG}-linux-amd64.tar.gz"
tar -xvf /tmp/etcd-${ETCD_TAG}-linux-amd64.tar.gz -C /tmp/
mv /tmp/etcd-${ETCD_TAG}-linux-amd64/etcd* /usr/local/bin/

# create etcd.conf
if [ -z "$KUBE_NODE_IP" ]; then
    KUBE_NODE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
fi

myip="${KUBE_NODE_IP}"
cert_dir="/etc/etcd/certs"
protocol="https"

if [ "$TLS_DISABLED" = "True" ]; then
    protocol="http"
fi

cat > /etc/etcd/etcd.conf <<EOF
ETCD_NAME="$myip"
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_CLIENT_URLS="$protocol://$myip:2379,http://127.0.0.1:2379"
ETCD_LISTEN_PEER_URLS="$protocol://$myip:2380"

ETCD_ADVERTISE_CLIENT_URLS="$protocol://$myip:2379,http://127.0.0.1:2379"
ETCD_INITIAL_ADVERTISE_PEER_URLS="$protocol://$myip:2380"
ETCD_DISCOVERY="$ETCD_DISCOVERY_URL"
EOF

if [ "$TLS_DISABLED" = "False" ]; then

cat >> /etc/etcd/etcd.conf <<EOF
ETCD_CA_FILE=$cert_dir/ca.crt
ETCD_TRUSTED_CA_FILE=$cert_dir/ca.crt
ETCD_CERT_FILE=$cert_dir/kubernetes.crt
ETCD_KEY_FILE=$cert_dir/kubernetes.key
ETCD_CLIENT_CERT_AUTH=true
ETCD_PEER_CA_FILE=$cert_dir/ca.crt
ETCD_PEER_TRUSTED_CA_FILE=$cert_dir/ca.crt
ETCD_PEER_CERT_FILE=$cert_dir/kubernetes.crt
ETCD_PEER_KEY_FILE=$cert_dir/kubernetes.key
ETCD_PEER_CLIENT_CERT_AUTH=true
EOF

fi

if [ -n "$HTTP_PROXY" ]; then
    echo "ETCD_DISCOVERY_PROXY=$HTTP_PROXY" >> /etc/etcd/etcd.conf
fi

# create systemd unit file for etcd service
cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
EnvironmentFile=/etc/etcd/etcd.conf
ExecStart=/usr/local/bin/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# debug
systemctl start etcd