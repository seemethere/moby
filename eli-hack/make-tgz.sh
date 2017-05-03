#!/usr/bin/env bash
set -e

DOCKER_CLIENT_BINARY_NAME='docker'
DOCKER_DAEMON_BINARY_NAME='dockerd'
DOCKER_RUNC_BINARY_NAME='docker-runc'
DOCKER_CONTAINERD_BINARY_NAME='docker-containerd'
DOCKER_CONTAINERD_CTR_BINARY_NAME='docker-containerd-ctr'
DOCKER_CONTAINERD_SHIM_BINARY_NAME='docker-containerd-shim'
DOCKER_PROXY_BINARY_NAME='docker-proxy'
DOCKER_INIT_BINARY_NAME='docker-init'

main() {
    local static_dest=$1
    local arch=""
}

main $1
