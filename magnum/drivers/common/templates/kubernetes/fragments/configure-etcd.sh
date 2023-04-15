. /etc/sysconfig/heat-params

set -x

if [ ! -z "$HTTP_PROXY" ]; then
    export HTTP_PROXY
fi

if [ ! -z "$HTTPS_PROXY" ]; then
    export HTTPS_PROXY
fi

if [ ! -z "$NO_PROXY" ]; then
    export NO_PROXY
fi

if [ -n "$ETCD_VOLUME_SIZE" ] && [ "$ETCD_VOLUME_SIZE" -gt 0 ]; then

    attempts=60
    while [ ${attempts} -gt 0 ]; do
        device_name=$(ls /dev/disk/by-id | grep ${ETCD_VOLUME:0:20} | head -n1)
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
    fstype=$(blkid -s TYPE -o value ${device_path} || echo "")
    if [ "${fstype}" != "xfs" ]; then
        mkfs.xfs -f ${device_path}
    fi
    mkdir -p /var/lib/etcd
    echo "${device_path} /var/lib/etcd xfs defaults 0 0" >> /etc/fstab
    mount -a
    chown -R etcd.etcd /var/lib/etcd
    chmod 755 /var/lib/etcd

fi

cat > /etc/systemd/system/etcd.service <<EOF
[Unit]
Description=Etcd server
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=/etc/sysconfig/heat-params
ExecStartPre=mkdir -p /var/lib/etcd
ExecStartPre=-/usr/local/bin/nerdctl rm etcd
ExecStart=/usr/local/bin/nerdctl run \\
    --name etcd \\
    --volume /usr/share/ca-certificates/mozilla:/etc/ssl/certs:ro,z \\
    --volume /etc/etcd:/etc/etcd:ro,z \\
    --volume /var/lib/etcd:/var/lib/etcd:rshared,z \\
    --net=host \\
    ${CONTAINER_INFRA_PREFIX:-"quay.io/coreos/"}etcd:${ETCD_TAG} \\
    /usr/local/bin/etcd \\
    --config-file /etc/etcd/etcd.conf.yaml
ExecStop=/usr/local/bin/nerdctl stop etcd
TimeoutStartSec=10min

[Install]
WantedBy=multi-user.target
EOF

if [ -z "$KUBE_NODE_IP" ]; then
    # FIXME(yuanying): Set KUBE_NODE_IP correctly
    KUBE_NODE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
fi

myip="${KUBE_NODE_IP}"
cert_dir="/etc/etcd/certs"
protocol="https"

if [ "$TLS_DISABLED" = "True" ]; then
    protocol="http"
fi

cat > /etc/etcd/etcd.conf.yaml <<EOF
# This is the configuration file for the etcd server.

# Human-readable name for this member.
name: "${INSTANCE_NAME}"

# Path to the data directory.
data-dir: /var/lib/etcd/default.etcd

# List of comma separated URLs to listen on for peer traffic.
listen-peer-urls: "$protocol://$myip:2380"

# List of comma separated URLs to listen on for client traffic.
listen-client-urls: "$protocol://$myip:2379,http://127.0.0.1:2379"

# List of this member's peer URLs to advertise to the rest of the cluster.
# The URLs needed to be a comma-separated list.
initial-advertise-peer-urls: "$protocol://$myip:2380"

# List of this member's client URLs to advertise to the public.
# The URLs needed to be a comma-separated list.
advertise-client-urls: "$protocol://$myip:2379,http://127.0.0.1:2379"

# Discovery URL used to bootstrap the cluster.
discovery: "$ETCD_DISCOVERY_URL"

EOF

if [ -n "$HTTP_PROXY" ]; then
    cat >> /etc/etcd/etcd.conf.yaml <<EOF
# HTTP proxy to use for traffic to discovery service.
discovery-proxy: $HTTP_PROXY

EOF
fi

if [ "$TLS_DISABLED" = "False" ]; then

    cat >> /etc/etcd/etcd.conf.yaml <<EOF
client-transport-security:
  # Path to the client server TLS cert file.
  cert-file: $cert_dir/server.crt

  # Path to the client server TLS key file.
  key-file: $cert_dir/server.key

  # Enable client cert authentication.
  client-cert-auth: true

  # Path to the client server TLS trusted CA cert file.
  trusted-ca-file: $cert_dir/ca.crt

peer-transport-security:
  # Path to the peer server TLS cert file.
  cert-file: $cert_dir/server.crt

  # Path to the peer server TLS key file.
  key-file: $cert_dir/server.key

  # Enable peer client cert authentication.
  client-cert-auth: true

  # Path to the peer server TLS trusted CA cert file.
  trusted-ca-file: $cert_dir/ca.crt
EOF
fi
# backwards compatible conf file
cat > /etc/etcd/etcd.conf <<EOF
ETCD_NAME="$INSTANCE_NAME"
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
ETCD_CERT_FILE=$cert_dir/server.crt
ETCD_KEY_FILE=$cert_dir/server.key
ETCD_CLIENT_CERT_AUTH=true
ETCD_PEER_CA_FILE=$cert_dir/ca.crt
ETCD_PEER_TRUSTED_CA_FILE=$cert_dir/ca.crt
ETCD_PEER_CERT_FILE=$cert_dir/server.crt
ETCD_PEER_KEY_FILE=$cert_dir/server.key
ETCD_PEER_CLIENT_CERT_AUTH=true
EOF

fi

if [ -n "$HTTP_PROXY" ]; then
    echo "ETCD_DISCOVERY_PROXY=$HTTP_PROXY" >> /etc/etcd/etcd.conf
fi
