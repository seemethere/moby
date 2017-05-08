#!/usr/bin/env bash
set -e

DOCKER_CLIENT_BINARY_NAME='docker'

find_static_binaries() {
    local where_to_pull=$1
    local version=$2
    # Pull regular files that are not symbolic links
    # Don't pull hash files
    find "$where_to_pull" \! -type l -type f | \
        sed '/md5/d; /sha256/d'
}

main() {
    source "eli-hack/make-static.sh"
    local version=$(< ./VERSION)
    local arch="$(go env GOARCH)"
    local os="$(go env GOOS)"
    local where_to_pull="bundles/$version/static/$os/$arch"
    local where_to_put="bundles/$version/eli-tgz/$os/$arch"
    local where_to_build="$where_to_put/build"
    local tar_base_dir="docker"
    local tar_path="$where_to_build/$tar_base_dir"
    local tgz_name="$where_to_put/$DOCKER_CLIENT_BINARY_NAME-$VERSION.tgz"

    echo "Checking if $where_to_pull exists..."
    if [[ ! -d "$where_to_pull" ]]; then
        echo "Static binaries not generated, exiting..."
        exit 1
    fi

    if [[ -d "$where_to_put" ]]; then
        echo "Removing $where_to_put"
        rm -rf $where_to_put
    fi

    # Build the build directory, it should build all the parents
    mkdir -p "$tar_path"
    echo "Copying over binary: /usr/local/bin/docker -> $tar_path/docker"
    cp /usr/local/bin/docker "$tar_path/"

    local static_binaries=$(find_static_binaries "$where_to_pull" "$version")
    for binary in $static_binaries; do
        # Strip `-$version` it's not needed in the tgz
        stripped_binary=$(basename "$binary" | sed "s/-$version//g")
        echo "Copying over binary: $binary -> $tar_path/$stripped_binary"
        cp "$binary" "$tar_path/$stripped_binary"
    done

    for shell in bash fish zsh; do
        echo "Copying over completion for shell: $shell -> $tar_path/completion/$shell"
        mkdir -p "$tar_path/completion/$shell"
        find "contrib/completion/$shell" \
            -type f \
            -name "*docker*" \
            -exec cp {} "$tar_path/completion/$shell" \;
    done


    echo "Create tgz from $where_to_build and naming it $tgz_name"
    tar \
        --numeric-owner --owner 0 \
        -C "$where_to_build" \
        -czf "$tgz_name" \
        "$tar_base_dir"

    hash_files "$tgz_name"

    echo "Cleaning up: $where_to_build"
    rm -rf "$where_to_build"

    echo "Created tgz: $tgz_name"
}

main
