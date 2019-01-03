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
    $MAGNUM_URL/certificates/$CLUSTER_UUID | python -c 'import sys, json; print json.load(sys.stdin)["pem"]' > $CA_CERT

function generate_certificates {
    _CERT=$cert_dir/${1}.crt
    _CSR=$cert_dir/${1}.csr
    _KEY=$cert_dir/${1}.key
    _CONF=$2

    # Generate client's private key and csr
    openssl genrsa -out "${_KEY}" 4096
    chmod 400 "${_KEY}"
    openssl req -new -days 1000 \
            -key "${_KEY}" \
            -out "${_CSR}" \
            -reqexts req_ext \
            -config "${_CONF}"

    # Send csr to Magnum to have it signed
    csr_req=$(python -c "import json; fp = open('${_CSR}'); print json.dumps({'cluster_uuid': '$CLUSTER_UUID', 'csr': fp.read()}); fp.close()")
    curl  $VERIFY_CA -X POST \
        -H "X-Auth-Token: $USER_TOKEN" \
        -H "OpenStack-API-Version: container-infra latest" \
        -H "Content-Type: application/json" \
        -d "$csr_req" \
        $MAGNUM_URL/certificates | python -c 'import sys, json; print json.load(sys.stdin)["pem"]' > ${_CERT}
}

INSTANCE_NAME=$(hostname --short | sed 's/\.novalocal//')
HOSTNAME=$(hostname)

# create config for kubelet
cat > ${cert_dir}/kubelet.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt = no
[req_distinguished_name]
CN = system:node:${INSTANCE_NAME}
O=system:nodes
OU=OpenStack/Magnum
C=JP
ST=Tokyo
L=Shibuya
[req_ext]
subjectAltName = IP:${KUBE_NODE_IP},DNS:${INSTANCE_NAME},DNS:${HOSTNAME}
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth,serverAuth
EOF

# create config for kube-proxy
cat > ${cert_dir}/proxy.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt = no
[req_distinguished_name]
CN = system:kube-proxy
O=system:node-proxier
OU=OpenStack/Magnum
C=JP
ST=Tokyo
L=Shibuya
[req_ext]
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
EOF

generate_certificates kubelet ${cert_dir}/kubelet.conf
generate_certificates proxy ${cert_dir}/proxy.conf

# set permission for certs direcotry
chmod 550 "${cert_dir}"
chmod 440 ${cert_dir}/kubelet.key
chmod 440 ${cert_dir}/proxy.key
