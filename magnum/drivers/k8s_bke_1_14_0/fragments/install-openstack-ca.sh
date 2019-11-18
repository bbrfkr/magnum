#!/bin/sh -ux

CA_FILE=/etc/pki/ca-trust/source/anchors/openstack-ca.pem

if [ -n "$OPENSTACK_CA" ] ; then
    cat >> $CA_FILE <<EOF
$OPENSTACK_CA
EOF
    chmod 444 $CA_FILE
    chown root:root $CA_FILE
    update-ca-trust extract

    sed -i 's@\[Service\]@[Service]\nEnvironment=REQUESTS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt@g' /var/lib/systemd/system/os-collect-config.service
    systemctl daemon-reload
    systemctl restart os-collect-config
fi
