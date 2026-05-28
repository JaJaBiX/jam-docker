# syntax=docker/dockerfile:1.7
# global arguments
ARG MAINTAINER='Jam https://github.com/joinmarket-webui'

ARG JAM_REPO=https://github.com/joinmarket-webui/jam
ARG JAM_REPO_REF=master

ARG JM_SERVER_REPO=https://github.com/JoinMarket-Org/joinmarket-clientserver
ARG JM_SERVER_REPO_REF=master

ARG SKIP_RELEASE_VERIFICATION=false
ARG JM_INSTALL_SCRIPT_ARGS='--disable-secp-check'

ARG NODE_IMAGE_VERSION=22.14.0
ARG NODE_IMAGE_HASH=9bef0ef1e268f60627da9ba7d7605e8831d5b56ad07487d24d1aa386336d1944
ARG NODE_IMAGE=node:${NODE_IMAGE_VERSION}-alpine3.21@sha256:${NODE_IMAGE_HASH}
ARG ALPINE_IMAGE_VERSION=3.21.2
ARG ALPINE_IMAGE_HASH=56fa17d2a7e7f168a043a2712e63aed1f8543aeafdcee47c58dcffe38ed51099
ARG ALPINE_IMAGE=alpine:${ALPINE_IMAGE_VERSION}@sha256:${ALPINE_IMAGE_HASH}
ARG DEBIAN_IMAGE_VERSION=bookworm-20250428-slim
ARG DEBIAN_IMAGE_HASH=4b50eb66f977b4062683ff434ef18ac191da862dbe966961bc11990cf5791a8d
ARG DEBIAN_IMAGE=debian:${DEBIAN_IMAGE_VERSION}@sha256:${DEBIAN_IMAGE_HASH}
ARG DINIT_IMAGE_VERSION=0.21.0
ARG DINIT_IMAGE_HASH=6ccfeea86d3ec4bbeb557c5c7da403091713d54706ab8ccd5ae89b54baddda9d
ARG DINIT_IMAGE=ghcr.io/joinmarket-webui/jam-contrib-dinit:${DINIT_IMAGE_VERSION}@sha256:${DINIT_IMAGE_HASH}

FROM --platform=$BUILDPLATFORM ${NODE_IMAGE} AS node

# --- Builder base 
FROM --platform=$BUILDPLATFORM ${ALPINE_IMAGE} AS builder-base
RUN apk add --no-cache --update git gnupg
# --- Builder base - end

# --- UI builder 
FROM builder-base AS ui-builder
ARG SKIP_RELEASE_VERIFICATION
ARG JAM_REPO
ARG JAM_REPO_REF
ARG JAM_REPO_RESOLVED_REF=unknown

COPY --from=node /usr/lib /usr/lib
COPY --from=node /usr/local/lib /usr/local/lib
COPY --from=node /usr/local/include /usr/local/include
COPY --from=node /usr/local/bin /usr/local/bin

WORKDIR /usr/src/jam

COPY pubkeys/ /pubkeys

# checkout and build project
RUN echo "JAM_REPO_RESOLVED_REF=$JAM_REPO_RESOLVED_REF" \
    && git clone "$JAM_REPO" . --depth=1 --branch "$JAM_REPO_REF" \
    && (if [ "$SKIP_RELEASE_VERIFICATION" != "true" ]; then \
        find /pubkeys -iname '*.asc' -exec gpg --import "{}" \; \
        && git verify-tag "$JAM_REPO_REF"; \
    fi) \
    && npm clean-install --no-fund --no-audit \
    && npm run build
# --- UI builder - end

FROM ${DINIT_IMAGE} AS dinit

# --- SERVER builder
FROM builder-base AS server-builder
ARG SKIP_RELEASE_VERIFICATION
ARG JM_SERVER_REPO
ARG JM_SERVER_REPO_REF
ARG JM_SERVER_REPO_RESOLVED_REF=unknown

WORKDIR /usr/src/joinmarket-clientserver

COPY pubkeys/ /pubkeys

RUN echo "JM_SERVER_REPO_RESOLVED_REF=$JM_SERVER_REPO_RESOLVED_REF" \
    && git clone "$JM_SERVER_REPO" . --depth=1 --branch "$JM_SERVER_REPO_REF" \
    && (if [ "$SKIP_RELEASE_VERIFICATION" != "true" ]; then \
        find /pubkeys -iname '*.asc' -exec gpg --import "{}" \; \
        && git verify-tag "$JM_SERVER_REPO_REF"; \
    fi)
# --- SERVER builder - end

# --- Native dependency builder
FROM ${DEBIAN_IMAGE} AS native-deps
ARG JM_INSTALL_SCRIPT_ARGS
ARG TARGETPLATFORM

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY --chmod=0755 build-native-deps.sh /usr/local/bin/build-native-deps
COPY pubkeys/third-party/ /pubkeys/third-party/

RUN apt-get update \
    && apt-get install --quiet --no-install-recommends --no-install-suggests --yes \
    ca-certificates curl gnupg build-essential automake autoconf pkg-config libtool \
    && rm --recursive --force /var/lib/apt/lists/*

RUN --mount=type=cache,id=jam-native-src-${TARGETPLATFORM},target=/var/cache/jam-native-src \
    build-native-deps $JM_INSTALL_SCRIPT_ARGS \
    && rm --recursive --force /tmp/jam-native-build /root/.gnupg
# --- Native dependency builder - end

# --- RUNTIME builder
FROM ${DEBIAN_IMAGE}
ARG MAINTAINER

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY --from=dinit /out/usr/bin /usr/bin
COPY --from=native-deps /opt/jam-native-root/ /
COPY --from=ui-builder /usr/src/jam/build /app
COPY --from=server-builder /usr/src/joinmarket-clientserver /src

RUN addgroup --system tor \
    && adduser --system --disabled-login --home /home/tor --ingroup tor --gecos 'tor user' tor \
    && apt-get update \
    && apt-get install --quiet --no-install-recommends --no-install-suggests --yes gnupg curl apt-transport-https ca-certificates \
    # add nginx debian repo
    && curl --silent https://nginx.org/keys/nginx_signing.key | \
    gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg > /dev/null \
    && sh -c "echo 'deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/debian bookworm nginx' > /etc/apt/sources.list.d/nginx.list" \
    && echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx > /dev/null \
    # add tor debian repo
    && curl --silent https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | \
    gpg --dearmor | tee /usr/share/keyrings/tor-archive-keyring.gpg > /dev/null \
    && sh -c "echo 'deb [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org bookworm main' > /etc/apt/sources.list.d/tor.list" \
    # install dependencies
    && apt-get update \
    && apt-get install --quiet --no-install-recommends --no-install-suggests --yes \
    # image dependencies
    tini iproute2 procps vim jq \
    # servers dependencies (see `install.sh`)
    build-essential automake autoconf pkg-config libtool python3-dev python3-pip python3-setuptools python3-venv libltdl-dev \
    # logrotate
    logrotate coreutils \
    # tor
    tor \
    obfs4proxy \
    deb.torproject.org-keyring \
    # ui dependencies
    nginx \
    # cleanup 
    && ldconfig \
    && apt-get clean \
    && rm --recursive --force /var/lib/apt/lists/*

ENV DATADIR=/root/.joinmarket
ENV CONFIG=${DATADIR}/joinmarket.cfg
ENV DEFAULT_CONFIG=/root/default.cfg
ENV PATH=/src/scripts:$PATH

WORKDIR /src

# install JoinMarket
ARG TARGETPLATFORM
RUN --mount=type=cache,id=jam-pip-${TARGETPLATFORM},target=/root/.cache/pip \
    pip3 config set global.break-system-packages true \
    && pip3 install --editable ".[services]" \
    && rm --recursive --force install.sh test/ .git/ .gitignore .github/ .coveragerc joinmarket-qt.desktop

# cleanup and remove ephemeral dependencies
RUN apt-get remove --purge --auto-remove --yes gnupg python3-pip apt-transport-https \
    && rm --force /var/log/dpkg.log

COPY default.cfg "${DEFAULT_CONFIG}"
COPY dinit-conf/* /etc/dinit.d/
COPY .bashrc /root/.bashrc
COPY --chown=tor:tor torrc /etc/tor/torrc

COPY nginx/snippets/proxy-params.conf /etc/nginx/snippets/proxy-params.conf
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

COPY --chmod=0755 jam-entrypoint.sh /

RUN mkdir --parents /var/lib/logrotate
COPY logrotate/* /etc/logrotate.d/

# ensure log directory exists (dinit files depend on it)
RUN mkdir --parents /var/log/jam

# keep version labels late so changing refs does not bust heavy build layers
ARG JAM_REPO_REF
ARG JM_SERVER_REPO_REF
LABEL maintainer="$MAINTAINER"
LABEL ui-version="$JAM_REPO_REF"
LABEL server-version="$JM_SERVER_REPO_REF"

# nginx default port
EXPOSE 80

WORKDIR /src/scripts

ENTRYPOINT  [ "tini", "-g", "--", "/jam-entrypoint.sh" ]
