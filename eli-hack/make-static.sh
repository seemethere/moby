#!/usr/bin/env bash
set -e

# The goal of this script is to simplify the creation of
# static binaries for both the client and the daemon

export PKG_CONFIG=${PKG_CONFIG:-pkg-config}


DOCKER_CLIENT_BINARY_NAME='docker'
DOCKER_DAEMON_BINARY_NAME='dockerd'
DOCKER_RUNC_BINARY_NAME='docker-runc'
DOCKER_CONTAINERD_BINARY_NAME='docker-containerd'
DOCKER_CONTAINERD_CTR_BINARY_NAME='docker-containerd-ctr'
DOCKER_CONTAINERD_SHIM_BINARY_NAME='docker-containerd-shim'
DOCKER_PROXY_BINARY_NAME='docker-proxy'
DOCKER_INIT_BINARY_NAME='docker-init'


gen_buildtags() {
    export DOCKER_BUILDTAGS="apparmor seccomp selinux"

    DOCKER_BUILDTAGS+=" daemon"
    if ${PKG_CONFIG} 'libsystemd >= 209' 2> /dev/null ; then
        DOCKER_BUILDTAGS+=" journald"
    elif ${PKG_CONFIG} 'libsystemd-journal' 2> /dev/null ; then
        DOCKER_BUILDTAGS+=" journald journald_compat"
    fi

    # test whether "btrfs/version.h" exists and apply btrfs_noversion appropriately
    if \
        command -v gcc &> /dev/null \
        && ! gcc -E - -o /dev/null &> /dev/null <<<'#include <btrfs/version.h>' \
    ; then
        DOCKER_BUILDTAGS+=' btrfs_noversion'
    fi

    # test whether "libdevmapper.h" is new enough to support deferred remove
    # functionality.
    if \
        command -v gcc &> /dev/null \
        && ! ( echo -e  '#include <libdevmapper.h>\nint main() { dm_task_deferred_remove(NULL); }'| gcc -xc - -o /dev/null -ldevmapper &> /dev/null ) \
    ; then
           DOCKER_BUILDTAGS+=' libdm_no_deferred_remove'
    fi
    LDFLAGS_STATIC=''
    EXTLDFLAGS_STATIC='-static'
    # ORIG_BUILDFLAGS is necessary for the cross target which cannot always build
    # with options like -race.
    ORIG_BUILDFLAGS=( -tags "autogen netgo static_build $DOCKER_BUILDTAGS" -installsuffix netgo )
    # see https://github.com/golang/go/issues/9369#issuecomment-69864440 for why -installsuffix is necessary here

    # When $DOCKER_INCREMENTAL_BINARY is set in the environment, enable incremental
    # builds by installing dependent packages to the GOPATH.
    REBUILD_FLAG="-a"
    if [ "$DOCKER_INCREMENTAL_BINARY" == "1" ] || [ "$DOCKER_INCREMENTAL_BINARY" == "true" ]; then
        REBUILD_FLAG="-i"
    fi
    ORIG_BUILDFLAGS+=( $REBUILD_FLAG )

    BUILDFLAGS=( $BUILDFLAGS "${ORIG_BUILDFLAGS[@]}" )
    # Test timeout.

    LDFLAGS_STATIC_DOCKER="
        $LDFLAGS_STATIC
        -extldflags \"$EXTLDFLAGS_STATIC\"
    "
}

hash_files() {
    while [ $# -gt 0 ]; do
        f="$1"
        shift
        dir="$(dirname "$f")"
        base="$(basename "$f")"
        for hashAlgo in md5 sha256; do
            if command -v "${hashAlgo}sum" &> /dev/null; then
                (
                    # subshell and cd so that we get output files like:
                    #   $HASH docker-$VERSION
                    # instead of:
                    #   $HASH /go/src/github.com/.../$VERSION/binary/docker-$VERSION
                    cd "$dir"
                    "${hashAlgo}sum" "$base" > "$base.$hashAlgo"
                )
            fi
        done
    done
}

build() {
    local short_name=$1
    local go_pkg=$2
    local binary_name="$short_name-$VERSION"
    local extension=""
    if [ "$(go env GOOS)" == 'windows' ]; then
        extension='.exe'
    fi
    local full_name="$binary_name$extension"

    echo "Building: $DEST/$full_name"
    # echo "BUILDFLAGS: ${BUILDFLAGS[@]}"
    # env
    # TODO: For this utilize gox to do cross compilation
    go build \
        -o "$DEST/$full_name" \
        "${BUILDFLAGS[@]}" \
        -ldflags "
            $LDFLAGS
            $LDFLAGS_STATIC_DOCKER
        " \
        $go_pkg
    echo "Created: $DEST/$full_name"

    ln -sf "$full_name" "$DEST/$short_name$extension"
    hash_files "$DEST/$full_name"
}

copy_binaries() {
    dir="$1"
    # Add nested executables to bundle dir so we have complete set of
    # them available, but only if the native OS/ARCH is the same as the
    # OS/ARCH of the build target
    if [ "$(go env GOOS)/$(go env GOARCH)" == "$(go env GOHOSTOS)/$(go env GOHOSTARCH)" ]; then
        if [ -x /usr/local/bin/docker-runc ]; then
            echo "Copying nested executables into $dir"
            for file in containerd containerd-shim containerd-ctr runc init proxy; do
                cp -f `which "docker-$file"` "$dir/"
                if [ "$2" == "hash" ]; then
                    hash_files "$dir/docker-$file"
                fi
            done
        fi
    fi
}

main() {
    gen_buildtags

    export VERSION=$(< ./VERSION)
    local arch="$(go env GOARCH)"
    local os="$(go env GOOS)"
    local version_dest="bundles/$VERSION"
    if [[ -d "$version_dest" ]]; then
        echo "Removing old directory: $version_dest"
        rm -rf "$version_dest"
    fi
    echo "Creating directory: $version_dest"
    export DEST="$version_dest/static/$os/$arch"
    mkdir -p "$DEST"

    source hack/make/.go-autogen

    build "$DOCKER_DAEMON_BINARY_NAME" 'github.com/docker/docker/cmd/dockerd'

    copy_binaries "$DEST" 'hash'
}

main
