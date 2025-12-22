runtime="containerd"
storage_dir="/var/lib/containerd"

clear_docker_storage () {
    # stop containerd
    systemctl stop ${runtime}
    # clear storage graph
    rm -rf ${storage_dir}/*
    mkdir -p ${storage_dir}
}

# Configure generic docker storage driver.
configure_storage_driver_generic() {
    clear_docker_storage

    if [ -n "$DOCKER_VOLUME_SIZE" ] && [ "$DOCKER_VOLUME_SIZE" -gt 0 ]; then
        mkfs.xfs -f ${device_path}
        echo "${device_path} ${storage_dir} xfs defaults 0 0" >> /etc/fstab
        mount -a
    fi
}
