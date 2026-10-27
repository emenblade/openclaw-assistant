#!/usr/bin/env bash
# First-run and startup wrapper for the OpenClaw assistant.
#
# Generates config/prompts/Himalaya config only when missing. Existing user
# edits are never overwritten. Then starts the OpenClaw Gateway.

set -euo pipefail
cd /app

STATE_DIR="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$STATE_DIR/openclaw.json}"
WORKSPACE="${OPENCLAW_WORKSPACE_DIR:-$STATE_DIR/workspace}"
OBSIDIAN_ROOT="${OBSIDIAN_ROOT:-$WORKSPACE/obsidian}"
HIMALAYA_CONFIG="${HIMALAYA_CONFIG:-$STATE_DIR/himalaya/config.toml}"
GOG_HOME="${GOG_HOME:-$STATE_DIR/gog}"

# Values consumed by the seeded prompts.
export TIMEZONE="${TZ:-UTC}"
export WORK_HOURS="${WORK_HOURS:-09:00-17:00}"
export CITY="${CITY:-}"
export QUIET_HOURS="${QUIET_HOURS:-22:00-07:00}"
export OWNER_NAME="${OWNER_NAME:-Owner}"
export ASSISTANT_NAME="${ASSISTANT_NAME:-Assistant}"
export OBSIDIAN_SUBDIR="${OBSIDIAN_SUBDIR:-Assistant}"

mkdir -p \
  "$STATE_DIR" \
  "$STATE_DIR/auth-profile-secrets" \
  "$STATE_DIR/cache" \
  "$STATE_DIR/npm-cache" \
  "$STATE_DIR/himalaya" \
  "$GOG_HOME" \
  "$WORKSPACE" \
  "$OBSIDIAN_ROOT/Assistant/Inbox" \
  "$OBSIDIAN_ROOT/Assistant/Daily" \
  "$OBSIDIAN_ROOT/Assistant/Topics"

# --- Discord plugin -----------------------------------------------------------
DISCORD_ENABLED=false
if [ -n "${DISCORD_BOT_TOKEN:-}" ] && [ -n "${DISCORD_OWNER_ID:-}" ]; then
  if [ ! -f "$STATE_DIR/.discord-plugin-installed" ]; then
    echo "[entrypoint] Installing OpenClaw Discord plugin..."
    if node dist/index.js plugins install @openclaw/discord; then
      touch "$STATE_DIR/.discord-plugin-installed"
      DISCORD_ENABLED=true
    else
      echo "[entrypoint] WARNING: Discord plugin install failed; Discord disabled." >&2
      DISCORD_ENABLED=false
    fi
  else
    DISCORD_ENABLED=true
  fi
fi
export DISCORD_ENABLED

# --- OpenClaw config ----------------------------------------------------------
if [ ! -f "$CONFIG_PATH" ]; then
  echo "[entrypoint] Rendering OpenClaw config..."
  node /opt/assistant/render-config.mjs \
    /opt/assistant/config/openclaw.template.json \
    "$CONFIG_PATH"
  chmod 600 "$CONFIG_PATH"
else
  echo "[entrypoint] Using existing config: $CONFIG_PATH"
fi

# --- Seed prompts -------------------------------------------------------------
for file in AGENTS.md SOUL.md USER.md IMPORTANCE.md TASKS.md; do
  if [ ! -f "$WORKSPACE/$file" ]; then
    echo "[entrypoint] Seeding $file"
    node /opt/assistant/render-file.mjs \
      "/opt/assistant/seed/$file" \
      "$WORKSPACE/$file"
  fi
done

# --- Himalaya ----------------------------------------------------------------
if [ -n "${GMAIL_APP_PASSWORD:-}" ] && [ ! -f "$HIMALAYA_CONFIG" ]; then
  echo "[entrypoint] Rendering Himalaya config..."
  /opt/assistant/render-himalaya.sh
fi

# --- gog (non-interactive setup only) ---------------------------------------
if [ -n "${GOG_KEYRING_PASSWORD:-}" ] && [ ! -f "$STATE_DIR/.gog-keyring-initialized" ]; then
  if gog auth keyring file >/dev/null 2>&1; then
    touch "$STATE_DIR/.gog-keyring-initialized"
  else
    echo "[entrypoint] WARNING: could not initialize gog file keyring." >&2
  fi
fi

if [ -f /home/node/google/client_secret.json ] && [ ! -f "$STATE_DIR/.gog-credentials-initialized" ]; then
  if gog auth credentials /home/node/google/client_secret.json >/dev/null 2>&1; then
    touch "$STATE_DIR/.gog-credentials-initialized"
    echo "[entrypoint] Loaded Google OAuth client credentials."
  else
    echo "[entrypoint] WARNING: could not load Google OAuth client credentials." >&2
  fi
fi

# --- Doctor + scoped exec allowlist -----------------------------------------
echo "[entrypoint] Running doctor..."
node dist/index.js doctor --fix --non-interactive || {
  echo "[entrypoint] WARNING: doctor reported issues; starting anyway." >&2
}

# The main agent may run only the scoped wrapper. This is idempotent.
node dist/index.js approvals allowlist add --agent "*" "/usr/local/bin/assistant-mail" \
  >/dev/null 2>&1 || true

echo "[entrypoint] Starting OpenClaw Gateway..."
exec node dist/index.js gateway \
  --bind "${OPENCLAW_GATEWAY_BIND:-lan}" \
  --port "${OPENCLAW_GATEWAY_PORT:-18789}"
