#!/bin/sh
set -eu

repo="$1"
ref="$2"
resolved_ref="$3"
skip_release_verification="$4"
pubkeys_dir="$5"

is_full_sha() {
    printf '%s' "$1" | grep -Eq '^[0-9a-fA-F]{40}$'
}

if is_full_sha "$ref"; then
    git clone --filter=blob:none --no-checkout "$repo" .
    git checkout --detach "$ref"
else
    git init .
    git remote add origin "$repo"
    git fetch --depth=1 origin "$ref"
    git checkout --detach FETCH_HEAD
fi

if [ "$resolved_ref" != "unknown" ] && [ -n "$resolved_ref" ]; then
    actual_ref="$(git rev-parse HEAD)"
    if [ "$actual_ref" != "$resolved_ref" ]; then
        echo "Fetched $actual_ref for $repo ref $ref, expected $resolved_ref" >&2
        exit 1
    fi
fi

if [ "$skip_release_verification" != "true" ]; then
    find "$pubkeys_dir" -iname '*.asc' -exec gpg --import "{}" \;
    git fetch --depth=1 origin "refs/tags/$ref:refs/tags/$ref"
    git verify-tag "$ref"
fi
