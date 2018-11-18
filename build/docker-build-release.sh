#!/bin/bash

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <distro> <docker-tag>"
    exit 1
fi

set -ex -o pipefail

distro="$1"
image="${distro,,}" # Docker image names are all-lowercase.
tag="$2"
arch='x86_64'
build_dir='/build'
container_name='kafkacat'

function docker-exec() {
    env_args=(
        -e DEBIAN_FRONTEND=noninteractive
    )
    docker exec -it "${env_args[@]}" "${container_name}" "$@"
}

# Clean only files ignored by Git (leaving any previously built binaries).
sudo git clean -dfX

# Delete the container from any previous run.
docker rm -f "${container_name}" 2>/dev/null || true

# Start a new container, mounting in the source repo.
docker run -itd --name "${container_name}" \
       --volume "$(pwd)":"${build_dir}" \
       --workdir "${build_dir}" \
       "${image}":"${tag}" \
       sleep infinity

# Install distro-specific dependencies needed for the build.
case "${image}" in
    centos|rhel)
        deps=(gcc gcc-c++ cmake make wget which cyrus-sasl-devel openssl-devel)
        docker-exec yum -q makecache
        docker-exec yum -q -y install "${deps[@]}" # Note: yum doesn't treat -qy as -q -y.
        ;;
    debian|ubuntu)
        deps=(gcc g++ cmake make wget libsasl2-dev libssl-dev)
        docker-exec apt-get -qq update
        docker-exec apt-get install -qy "${deps[@]}"
        ;;
    *)
        echo "error: unknown distro/image '${image}'"
        exit 1
esac

# Do the actual build.
docker-exec ./bootstrap.sh build/release.conf

# Save off the build artifact.
BINARY_NAME="kafkacat-${distro}-${tag}-${arch}"
echo "Preparing release binary '${BINARY_NAME}'..."
strip kafkacat
mv kafkacat ${BINARY_NAME}

# Leave the container running to facilitate debugging in non-CI environments.
