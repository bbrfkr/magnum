#!/bin/bash -v

. /etc/sysconfig/heat-params

if [ "$VERIFY_CA" == "True" ]; then
    verify_ca=""
else
    verify_ca="-k"
fi

$WAIT_CURL $verify_ca --data-binary '{"status": "SUCCESS"}'
