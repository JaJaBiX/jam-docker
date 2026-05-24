#!/usr/bin/env bash
set -euo pipefail

upstream_remote="${UPSTREAM_REMOTE:-upstream}"
upstream_url="${UPSTREAM_REPO_URL:-https://github.com/joinmarket-webui/jam-docker.git}"
upstream_branch="${UPSTREAM_BRANCH:-master}"
upstream_ref="${UPSTREAM_REF:-${upstream_remote}/${upstream_branch}}"
expected_repo="${EXPECTED_UPSTREAM_JM_SERVER_REPO:-https://github.com/JoinMarket-Org/joinmarket-clientserver}"

if ! git remote get-url "${upstream_remote}" >/dev/null 2>&1; then
  git remote add "${upstream_remote}" "${upstream_url}"
else
  git remote set-url "${upstream_remote}" "${upstream_url}"
fi

git fetch --quiet "${upstream_remote}" "${upstream_branch}"

upstream_env="$(git show "${upstream_ref}:.env")"
upstream_repo="$(printf '%s\n' "${upstream_env}" | awk -F= '/^JM_SERVER_REPO=/ {print $2; exit}')"

if [ -z "${upstream_repo}" ]; then
  echo "::warning title=Cannot inspect upstream JM_SERVER_REPO::Upstream .env has no JM_SERVER_REPO entry."
  echo "WARNING: upstream .env has no JM_SERVER_REPO entry."
  exit 0
fi

if [ "${upstream_repo}" != "${expected_repo}" ]; then
  echo "::warning title=Upstream JM_SERVER_REPO changed::Upstream jam-docker now points JM_SERVER_REPO=${upstream_repo}; expected ${expected_repo}. This may mean JoinMarket clientserver has a new active upstream owner. Review and sync our joinmarket-clientserver fork before publishing images."
  cat <<EOF
WARNING: upstream JM_SERVER_REPO changed.

Expected archived upstream:
  ${expected_repo}

Current upstream jam-docker value:
  ${upstream_repo}

This may mean JoinMarket clientserver has a new active upstream owner.
Review that repository and sync git@github-ivanpod:JaJaBiX/joinmarket-clientserver.git
before publishing new images.
EOF
fi
