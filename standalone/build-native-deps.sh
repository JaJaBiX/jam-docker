#!/usr/bin/env bash

set -euo pipefail

cache_dir="${JAM_NATIVE_CACHE_DIR:-/var/cache/jam-native-src}"
build_dir="${JAM_NATIVE_BUILD_DIR:-/tmp/jam-native-build}"
destdir="${JAM_NATIVE_DESTDIR:-/opt/jam-native-root}"
prefix="${JAM_NATIVE_PREFIX:-/usr}"
use_secp_check=1
no_gpg_validation=0

for arg in "$@"; do
    case "$arg" in
        --disable-secp-check)
            use_secp_check=0
            ;;
        --no-gpg-validation)
            no_gpg_validation=1
            ;;
        --disable-os-deps-check|--docker-install|--without-qt)
            ;;
        "")
            ;;
        *)
            echo "Unsupported native dependency build option: $arg" >&2
            exit 1
            ;;
    esac
done

mkdir --parents "$cache_dir" "$build_dir" "$destdir"

make_cmd="make"
if command -v gmake > /dev/null 2>&1; then
    make_cmd="gmake"
fi

make_jobs="$(nproc)"
export MAKEFLAGS="-j $make_jobs"

sha256_verify()
{
    local expected="$1"
    local file="$2"
    sha256sum -c <<<"$expected  $file"
}

http_get()
{
    local url="$1"
    local file="$2"
    curl --fail --location --retry 5 "$url" --output "$file"
}

gpg_verify()
{
    local key_file="$1"
    local sig_file="$2"
    local data_file="$3"

    if [[ "$no_gpg_validation" == 1 ]]; then
        return 0
    fi

    gpg --batch --import "$key_file"
    gpg --batch --verify "$sig_file" "$data_file"
}

fetch_tarball()
{
    local pkg_name="$1"
    local pkg_hash="$2"
    local pkg_url="$3"
    local pkg_pubkeys="${4:-}"
    local pkg_sig="${5:-}"

    local cached_pkg="$cache_dir/$pkg_name"

    if [[ ! -f "$cached_pkg" ]] || ! sha256_verify "$pkg_hash" "$cached_pkg"; then
        http_get "$pkg_url/$pkg_name" "$cached_pkg"
    fi
    sha256_verify "$pkg_hash" "$cached_pkg"

    if [[ -n "$pkg_sig" ]]; then
        local cached_sig="$cache_dir/$pkg_sig"
        http_get "$pkg_url/$pkg_sig" "$cached_sig"
        gpg_verify "/pubkeys/third-party/$pkg_pubkeys" "$cached_sig" "$cached_pkg"
    fi

    tar --extract --gzip --file "$cached_pkg" --directory "$build_dir"
}

build_libsecp256k1()
{
    local secp256k1_version="0.5.0"
    local secp256k1_lib_tar="v$secp256k1_version.tar.gz"
    local secp256k1_lib_sha="07934fde88c677abbc4d42c36ef7ef8d3850cd0c065e4f976f66f4f97502c95a"
    local secp256k1_lib_url="https://github.com/bitcoin-core/secp256k1/archive/refs/tags"

    fetch_tarball "$secp256k1_lib_tar" "$secp256k1_lib_sha" "$secp256k1_lib_url"

    pushd "$build_dir/secp256k1-$secp256k1_version" > /dev/null
    ./autogen.sh
    ./configure \
        --enable-module-recovery \
        --prefix "$prefix" \
        --enable-experimental \
        --enable-module-ecdh \
        --enable-benchmark=no \
        MAKE="$make_cmd"
    "$make_cmd"
    if [[ "$use_secp_check" == 1 ]]; then
        "$make_cmd" check
    else
        echo "Skipping libsecp256k1 tests."
    fi
    "$make_cmd" DESTDIR="$destdir" install
    popd > /dev/null
}

build_libsodium()
{
    local sodium_version="libsodium-1.0.20"
    local sodium_lib_tar="${sodium_version}.tar.gz"
    local sodium_lib_sha="ebb65ef6ca439333c2bb41a0c1990587288da07f6c7fd07cb3a18cc18d30ce19"
    local sodium_url="https://download.libsodium.org/libsodium/releases"
    local sodium_pubkeys="libsodium.asc"

    fetch_tarball "$sodium_lib_tar" "$sodium_lib_sha" "$sodium_url" \
        "$sodium_pubkeys" "${sodium_lib_tar}.sig"

    pushd "$build_dir/$sodium_version" > /dev/null
    ./autogen.sh DO_NOT_UPDATE_CONFIG_SCRIPTS=1
    ./configure \
        --enable-minimal \
        --enable-shared \
        --prefix="$prefix"
    "$make_cmd"
    "$make_cmd" check
    "$make_cmd" DESTDIR="$destdir" install
    popd > /dev/null
}

rm --recursive --force "$build_dir"
mkdir --parents "$build_dir"

build_libsecp256k1
build_libsodium
