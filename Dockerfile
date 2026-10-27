# OpenClaw assistant for Unraid.
#
# Adds gog (Google Workspace CLI), Himalaya (IMAP/SMTP), ffmpeg, jq, and a
# scoped mail/calendar/notes wrapper. Runs as the base image's non-root node
# user (UID/GID 1000).
#
# Build:
#   docker build -t openclaw-assistant:local .
#
# This image supports linux/amd64 only. Unraid x86_64 is amd64.

ARG OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:2026.10.7
FROM ${OPENCLAW_IMAGE}

USER root

ARG GOG_VERSION=0.47.0
ARG HIMALAYA_VERSION=2.2.1
ARG GOG_SHA256=c3ed94efca90c754cdda300e3c7f8cc2f3d7df86d3fdc5d11f996c7518a09c24
ARG HIMALAYA_SHA256=5c5ba2724c162f82d0a0c71b6c03224ed44f8bef7b14ace5da0635d3af2665a0
ARG TARGETARCH=amd64

RUN set -eux; \
    if [ "${TARGETARCH}" != "amd64" ]; then \
      echo "This image currently supports linux/amd64 only (Unraid x86_64)." >&2; \
      exit 1; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      ffmpeg \
      gzip \
      jq \
      ripgrep \
      tar; \
    rm -rf /var/lib/apt/lists/*

# gog (Google Workspace CLI)
RUN set -eux; \
    mkdir -p /tmp/gog; \
    curl -fsSL \
      "https://github.com/openclaw/gogcli/releases/download/v${GOG_VERSION}/gogcli_${GOG_VERSION}_linux_amd64.tar.gz" \
      -o /tmp/gog.tgz; \
    echo "${GOG_SHA256}  /tmp/gog.tgz" | sha256sum -c -; \
    tar --no-same-owner --no-same-permissions -xzf /tmp/gog.tgz -C /tmp/gog; \
    install -m 0755 /tmp/gog/gog /usr/local/bin/gog; \
    rm -rf /tmp/gog /tmp/gog.tgz; \
    gog --version

# Himalaya (IMAP/SMTP)
RUN set -eux; \
    mkdir -p /tmp/himalaya; \
    curl -fsSL \
      "https://github.com/pimalaya/himalaya/releases/download/v${HIMALAYA_VERSION}/himalaya.x86_64-linux.tgz" \
      -o /tmp/himalaya.tgz; \
    echo "${HIMALAYA_SHA256}  /tmp/himalaya.tgz" | sha256sum -c -; \
    tar --no-same-owner --no-same-permissions -xzf /tmp/himalaya.tgz -C /tmp/himalaya himalaya; \
    install -m 0755 /tmp/himalaya/himalaya /usr/local/bin/himalaya; \
    rm -rf /tmp/himalaya /tmp/himalaya.tgz; \
    himalaya --version

# Scoped mail/calendar/notes wrapper. This is the only executable the main
# agent is allowlisted to run.
COPY assistant-mail /usr/local/bin/assistant-mail
COPY entrypoint.sh /usr/local/bin/assistant-entrypoint.sh
COPY render-config.mjs /opt/assistant/render-config.mjs
COPY render-file.mjs /opt/assistant/render-file.mjs
COPY render-himalaya.sh /opt/assistant/render-himalaya.sh
COPY config /opt/assistant/config
COPY seed /opt/assistant/seed

RUN chmod 0755 \
      /usr/local/bin/assistant-mail \
      /usr/local/bin/assistant-entrypoint.sh \
      /opt/assistant/render-himalaya.sh; \
    chmod 0644 \
      /opt/assistant/render-config.mjs \
      /opt/assistant/render-file.mjs \
      /opt/assistant/config/openclaw.template.json \
      /opt/assistant/seed/*.md; \
    if [ ! -e /usr/local/bin/openclaw ]; then \
      printf '%s\n' '#!/bin/sh' 'exec node /app/dist/index.js "$@"' > /usr/local/bin/openclaw; \
      chmod 0755 /usr/local/bin/openclaw; \
    fi

ENV HOME=/home/node \
    OPENCLAW_HOME=/home/node \
    OPENCLAW_STATE_DIR=/home/node/.openclaw \
    OPENCLAW_CONFIG_DIR=/home/node/.openclaw \
    OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json \
    OPENCLAW_WORKSPACE_DIR=/home/node/.openclaw/workspace \
    OPENCLAW_AUTH_PROFILE_SECRET_DIR=/home/node/.openclaw/auth-profile-secrets \
    OPENCLAW_GATEWAY_PORT=18789 \
    OPENCLAW_GATEWAY_BIND=lan \
    OPENCLAW_DISABLE_BONJOUR=1 \
    GOG_HOME=/home/node/.openclaw/gog \
    HIMALAYA_CONFIG=/home/node/.openclaw/himalaya/config.toml \
    OBSIDIAN_ROOT=/home/node/.openclaw/workspace/obsidian \
    XDG_CACHE_HOME=/home/node/.openclaw/cache \
    NPM_CONFIG_CACHE=/home/node/.openclaw/npm-cache \
    PATH=/home/node/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

EXPOSE 18789

USER node

ENTRYPOINT ["/usr/local/bin/assistant-entrypoint.sh"]
