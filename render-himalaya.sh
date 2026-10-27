#!/usr/bin/env bash
# Generate a minimal Himalaya Gmail config from environment variables.
# This runs as the container user (UID 1000) and never overwrites an existing
# config. App passwords are alphanumeric, so basic TOML string interpolation is
# sufficient here.

set -euo pipefail

: "${ASSISTANT_EMAIL:?ASSISTANT_EMAIL is required}"
: "${GMAIL_APP_PASSWORD:?GMAIL_APP_PASSWORD is required}"

CONFIG_FILE="${HIMALAYA_CONFIG:-/home/node/.openclaw/himalaya/config.toml}"
CONFIG_DIR="$(dirname "$CONFIG_FILE")"

install -d -m 700 "$CONFIG_DIR"
umask 077

cat > "$CONFIG_FILE" <<EOF
[accounts.assistant]
default = true
email = "${ASSISTANT_EMAIL}"
display-name = "Assistant"

imap.server = "imaps://imap.gmail.com:993"
imap.sasl.plain.username = "${ASSISTANT_EMAIL}"
imap.sasl.plain.password.raw = "${GMAIL_APP_PASSWORD}"

smtp.server = "smtps://smtp.gmail.com:465"
smtp.sasl.plain.username = "${ASSISTANT_EMAIL}"
smtp.sasl.plain.password.raw = "${GMAIL_APP_PASSWORD}"
EOF

chmod 600 "$CONFIG_FILE"
printf 'Wrote %s\n' "$CONFIG_FILE"
