set +x

echo "START: install cri"

. /etc/sysconfig/heat-params
set -x

# setting containerd
if [ -n "${DOCKERHUB_PROXY_URL}" ] ; then
  cat /etc/containerd/config.toml | \
  yj -tj | \
  jq ".plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors.\"docker.io\".endpoint |= .+ [\"$DOCKERHUB_PROXY_URL\"]" | \
  yj -jt > /tmp/config.toml
  mv /tmp/config.toml /etc/containerd/config.toml
fi

if [ "$(echo "${USE_GPU}" | tr '[:upper:]' '[:lower:]')" = "true" ] ; then
  nvidia-ctk runtime configure --runtime=containerd
fi

# enable containerd
curl -o /lib/systemd/system/containerd.service https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
systemctl daemon-reload
systemctl enable containerd
systemctl start containerd

echo "END: install cri"
