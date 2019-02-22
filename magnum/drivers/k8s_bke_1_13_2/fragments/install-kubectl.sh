#!/bin/sh

. /etc/sysconfig/heat-params

rpm -qa wget > /dev/null
if [ $? -ne 0 ] ; then
  yum -y install wget
fi

wget -O /usr/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/${KUBE_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/bin/kubectl
