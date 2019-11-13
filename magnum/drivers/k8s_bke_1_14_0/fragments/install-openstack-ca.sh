#!/bin/sh -ux

CA_FILE=/etc/pki/ca-trust/source/anchors/openstack-ca.pem

if [ -n "$OPENSTACK_CA" ] ; then
    cat >> $CA_FILE <<EOF
$OPENSTACK_CA
EOF
    cat >> /opt/stack/venvs/os-collect-config/lib/python2.7/site-packages/requests/cacert.pem <<EOF
$OPENSTACK_CA
EOF
    chmod 444 $CA_FILE
    chown root:root $CA_FILE
    update-ca-trust extract
fi
