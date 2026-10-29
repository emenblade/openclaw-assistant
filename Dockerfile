# OpenClaw assistant for Unraid.
#
# Adds Himalaya (IMAP/SMTP), ffmpeg, jq, ripgrep, a service-account Google
# Calendar CLI, and a scoped mail/calendar/notes wrapper. Runs as the base
# image's non-root node user (UID/GID 1000).
#
# Build:
#   docker build -t openclaw-assistant:local .
#
# This image supports linux/amd64 only. Unraid x86_64 is amd64.

ARG OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:2026.10.7
FROM ${OPENCLAW_IMAGE}

USER root

ARG HIMALAYA_VERSION=2.2.1
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
      tar \
      util-linux; \
    rm -rf /var/lib/apt/lists/*

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

# Scoped wrapper + service-account Calendar CLI. These are the only
# assistant-facing executables for mail/calendar/notes.
COPY assistant-mail /usr/local/bin/assistant-mail
COPY gcal.mjs /usr/local/bin/gcal
COPY entrypoint.sh /usr/local/bin/assistant-entrypoint.sh
COPY render-config.mjs /opt/assistant/render-config.mjs
COPY render-file.mjs /opt/assistant/render-file.mjs
COPY render-himalaya.sh /opt/assistant/render-himalaya.sh
COPY config /opt/assistant/config
COPY seed /opt/assistant/seed

RUN chmod 0755 \
      /usr/local/bin/assistant-mail \
      /usr/local/bin/gcal \
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

ENV HOME=/home/node/.openclaw/home \
    OPENCLAW_HOME=/home/node/.openclaw/home \
    OPENCLAW_STATE_DIR=/home/node/.openclaw \
    OPENCLAW_CONFIG_DIR=/home/node/.openclaw \
    OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json \
    OPENCLAW_WORKSPACE_DIR=/home/node/.openclaw/workspace \
    OPENCLAW_AUTH_PROFILE_SECRET_DIR=/home/node/.openclaw/auth-profile-secrets \
    OPENCLAW_GATEWAY_PORT=18789 \
    OPENCLAW_GATEWAY_BIND=lan \
    OPENCLAW_DISABLE_BONJOUR=1 \
    GOOGLE_SERVICE_ACCOUNT_JSON=/home/node/.openclaw/google/service-account.json \
    HIMALAYA_CONFIG=/home/node/.openclaw/himalaya/config.toml \
    OBSIDIAN_ROOT=/home/node/obsidian \
    XDG_CONFIG_HOME=/home/node/.openclaw/home/.config \
    XDG_DATA_HOME=/home/node/.openclaw/home/.local/share \
    XDG_STATE_HOME=/home/node/.openclaw/home/.local/state \
    XDG_CACHE_HOME=/home/node/.openclaw/cache \
    NPM_CONFIG_CACHE=/home/node/.openclaw/npm-cache \
    PATH=/home/node/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin

EXPOSE 18789

USER root

ENTRYPOINT ["/usr/local/bin/assistant-entrypoint.sh"]
