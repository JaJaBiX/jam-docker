#!/usr/bin/env bash
set -euo pipefail

set_env() {
  key="$1"
  value="$2"

  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '\n%s=%s\n' "${key}" "${value}" >> .env
  fi
}

set_env "JM_SERVER_REPO" "https://github.com/JaJaBiX/joinmarket-clientserver"
set_env "JM_SERVER_REPO_REF" "master"
set_env "SKIP_RELEASE_VERIFICATION" "true"

sed -i \
  -e 's|image_name_prefix: joinmarket-webui/jam-|image_name_prefix: jajabix/jam-|g' \
  -e 's|image_name_prefix: joinmarket-webui/jam-dev-|image_name_prefix: jajabix/jam-dev-|g' \
  .github/workflows/create-and-publish-docker-on-release.yml \
  .github/workflows/create-and-publish-docker-dev-manually.yml
