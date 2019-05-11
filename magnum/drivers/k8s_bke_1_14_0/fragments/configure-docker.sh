#!/bin/sh

. /etc/sysconfig/heat-params

# install docker
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce-18.09.0
mkdir -p /etc/docker

if [ -n "$DOCKER_VOLUME_SIZE" ] && [ "$DOCKER_VOLUME_SIZE" -gt 0 ]; then
    if [ "$ENABLE_CINDER" == "False" ]; then
        # FIXME(yuanying): Use ephemeral disk for docker storage
        # Currently Ironic doesn't support cinder volumes,
        # so we must use preserved ephemeral disk instead of a cinder volume.
        device_path=$(readlink -f /dev/disk/by-label/ephemeral0)
    else
        attempts=60
        while [ ${attempts} -gt 0 ]; do
            device_name=$(ls /dev/disk/by-id | grep ${DOCKER_VOLUME:0:20}$)
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
    fi
fi

# Configure generic docker storage driver.
configure_storage_driver_generic() {
    if [ -n "$DOCKER_VOLUME_SIZE" ] && [ "$DOCKER_VOLUME_SIZE" -gt 0 ]; then
        mkfs.xfs -f ${device_path}
        echo "${device_path} /var/lib/docker xfs defaults 0 0" >> /etc/fstab
        mount -a
    fi

    cat <<EOF > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=${CGROUP_DRIVER}"],
  "storage-driver": "$1"
}
EOF
}

# Configure docker storage with devicemapper using direct LVM
configure_devicemapper () {
    cat <<EOF > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=${CGROUP_DRIVER}"],
  "storage-driver": "devicemapper",
  "storage-opts": [
    "dm.directlvm_device=/dev/sdb",
    "dm.thinp_percent=95",
    "dm.thinp_metapercent=1",
    "dm.thinp_autoextend_threshold=80",
    "dm.thinp_autoextend_percent=20",
    "dm.directlvm_device_force=false"
  ]
}
EOF
}

if [ "$DOCKER_STORAGE_DRIVER" = "devicemapper" ]; then
    configure_devicemapper
else
    configure_storage_driver_generic $DOCKER_STORAGE_DRIVER
fi

# enable and start docker
systemctl enable docker
systemctl start docker
