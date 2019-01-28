#!/bin/sh

. /etc/sysconfig/heat-params

set -x
set -o errexit
set -o nounset
set -o pipefail

if [ "$TLS_DISABLED" == "True" ]; then
    exit 0
fi

if [ "$VERIFY_CA" == "True" ]; then
    VERIFY_CA=""
else
    VERIFY_CA="-k"
fi

if [ -z "${KUBE_NODE_IP}" ]; then
    KUBE_NODE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
fi

sans="IP:${KUBE_NODE_IP}"

if [ -z "${KUBE_NODE_PUBLIC_IP}" ]; then
    KUBE_NODE_PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
fi

if [ -n "${KUBE_NODE_PUBLIC_IP}" ]; then
    sans="${sans},IP:${KUBE_NODE_PUBLIC_IP}"
fi

if [ "${KUBE_NODE_PUBLIC_IP}" != "${KUBE_API_PUBLIC_ADDRESS}" ] \
        && [ -n "${KUBE_API_PUBLIC_ADDRESS}" ]; then
    sans="${sans},IP:${KUBE_API_PUBLIC_ADDRESS}"
fi

if [ "${KUBE_NODE_IP}" != "${KUBE_API_PRIVATE_ADDRESS}" ] \
        && [ -n "${KUBE_API_PRIVATE_ADDRESS}" ]; then
    sans="${sans},IP:${KUBE_API_PRIVATE_ADDRESS}"
fi

MASTER_HOSTNAME=${MASTER_HOSTNAME:-}
if [ -n "${MASTER_HOSTNAME}" ]; then
    sans="${sans},DNS:${MASTER_HOSTNAME}"
fi

if [ -n "${ETCD_LB_VIP}" ]; then
    sans="${sans},IP:${ETCD_LB_VIP}"
fi

sans="${sans},IP:127.0.0.1"

KUBE_SERVICE_IP=$(echo $PORTAL_NETWORK_CIDR | awk 'BEGIN{FS="[./]"; OFS="."}{print $1,$2,$3,$4 + 1}')

sans="${sans},IP:${KUBE_SERVICE_IP}"

sans="${sans},DNS:kubernetes,DNS:kubernetes.default,DNS:kubernetes.default.svc,DNS:kubernetes.default.svc.cluster.local"

echo "sans is ${sans}"
cert_dir=/etc/kubernetes/certs
mkdir -p "$cert_dir"
CA_CERT=$cert_dir/ca.crt

#Get a token by user credentials and trust
auth_json=$(cat << EOF
{
    "auth": {
        "identity": {
            "methods": [
                "password"
            ],
            "password": {
                "user": {
                    "id": "$TRUSTEE_USER_ID",
                    "password": "$TRUSTEE_PASSWORD"
                }
            }
        }
    }
}
EOF
)
content_type='Content-Type: application/json'
url="$AUTH_URL/auth/tokens"
USER_TOKEN=`curl $VERIFY_CA -s -i -X POST -H "$content_type" -d "$auth_json" $url \
    | grep -i X-Subject-Token | awk '{print $2}' | tr -d '[[:space:]]'`

# Get CA certificate for this cluster
curl $VERIFY_CA -X GET \
    -H "X-Auth-Token: $USER_TOKEN" \
    -H "OpenStack-API-Version: container-infra latest" \
    $MAGNUM_URL/certificates/$CLUSTER_UUID | python -c 'import sys, json; print json.load(sys.stdin)["pem"]' > ${CA_CERT}

function generate_certificates {
    _CERT=$cert_dir/${1}.crt
    _CSR=$cert_dir/${1}.csr
    _KEY=$cert_dir/${1}.key
    _CONF=$2

    # Generate server's private key and csr
    openssl genrsa -out "${_KEY}" 4096
    chmod 400 "${_KEY}"
    openssl req -new -days 1000 \
            -key "${_KEY}" \
            -out "${_CSR}" \
            -reqexts req_ext \
            -config "${_CONF}"

    # Send csr to Magnum to have it signed
    csr_req=$(python -c "import json; fp = open('${_CSR}'); print json.dumps({'cluster_uuid': '$CLUSTER_UUID', 'csr': fp.read()}); fp.close()")
    curl $VERIFY_CA -X POST \
        -H "X-Auth-Token: $USER_TOKEN" \
        -H "OpenStack-API-Version: container-infra latest" \
        -H "Content-Type: application/json" \
        -d "$csr_req" \
        $MAGNUM_URL/certificates | python -c 'import sys, json; print json.load(sys.stdin)["pem"]' > ${_CERT}
}

# Create config for kubernetes(for apiserver and etcd) csr
cat > ${cert_dir}/kubernetes.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt = no
[req_distinguished_name]
CN = kubernetes
[req_ext]
subjectAltName = ${sans}
extendedKeyUsage = clientAuth,serverAuth
EOF

#admin user Certs
cat > ${cert_dir}/admin.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt = no
[req_distinguished_name]
CN = admin
O=system:masters
OU=OpenStack/Magnum
C=JP
ST=Tokyo
L=Shibuya
[req_ext]
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
EOF

#kube-controller-manager Certs
cat > ${cert_dir}/controller-manager.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt = no
[req_distinguished_name]
CN = system:kube-controller-manager
O=system:kube-controller-manager
OU=OpenStack/Magnum
C=JP
ST=Tokyo
L=Shibuya
[req_ext]
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
EOF

#kube-scheculer Certs
cat > ${cert_dir}/scheduler.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt = no
[req_distinguished_name]
CN = system:kube-scheduler
O=system:kube-scheduler
OU=OpenStack/Magnum
C=JP
ST=Tokyo
L=Shibuya
[req_ext]
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
EOF

#front-proxy-client Certs
cat > ${cert_dir}/front-proxy-client.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt = no
[req_distinguished_name]
CN = front-proxy-client
[req_ext]
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
EOF

generate_certificates kubernetes ${cert_dir}/kubernetes.conf
generate_certificates admin ${cert_dir}/admin.conf
generate_certificates controller-manager ${cert_dir}/controller-manager.conf
generate_certificates scheduler ${cert_dir}/scheduler.conf
generate_certificates front-proxy ${cert_dir}/front-proxy-client.conf

# Generate service account key and private key
echo -e "${KUBE_SERVICE_ACCOUNT_KEY}" > ${cert_dir}/service_account.key
echo -e "${KUBE_SERVICE_ACCOUNT_PRIVATE_KEY}" > ${cert_dir}/service_account_private.key

# set permission and create certs direcotry for etcd
chmod 550 "${cert_dir}"
chmod 440 $cert_dir/kubernetes.key
mkdir -p /etc/etcd/certs
cp ${cert_dir}/* /etc/etcd/certs
