# OpenClaw Assistant for Unraid

A private, self-hosted personal assistant container:

- OpenClaw Gateway
- Discord bot for text and notifications
- OpenClaw Android/Wear OS app for voice/Talk
- Gmail IMAP/SMTP via Himalaya
- Google Calendar via gog
- Obsidian notes
- OpenCode Zen models
- WireGuard-only networking
- No Docker socket, no privileged mode

This repo is designed for the user's Unraid NAS and Galaxy S25 + Galaxy Watch 7.

## Why OpenClaw

OpenClaw has the only official Android + Wear OS experience with a watch Tile/Talk and on-device speech. Hermes Agent is a strong alternative for memory/self-improvement, but it has no official Wear OS Tile/Talk equivalent. See the docs in the shared planning folder for the full comparison.

## Requirements

- Unraid with Docker
- WireGuard access to the NAS
- 32 GB RAM is plenty; this container is capped at 1 GB RAM / 2 CPUs
- Dedicated Google account
- Google Cloud project with Calendar API and a Desktop OAuth client
- Discord bot application (new bot, not an existing Red bot token)
- OpenCode Zen API key
- Obsidian vault path

## Quick start

### 1. Build the image

On the Unraid NAS:

```bash
git clone https://github.com/emenblade/openclaw-assistant.git
cd openclaw-assistant
docker build -t openclaw-assistant:local .
```

Or use the published GHCR image after the GitHub Actions workflow runs:

```text
ghcr.io/emenblade/openclaw-assistant:latest
```

### 2. Prepare appdata

```bash
mkdir -p /mnt/cache/appdata/openclaw-assistant/google
chown -R 1000:1000 /mnt/cache/appdata/openclaw-assistant
chmod 700 /mnt/cache/appdata/openclaw-assistant
```

Put your Google Desktop OAuth `client_secret.json` in:

```text
/mnt/cache/appdata/openclaw-assistant/google/client_secret.json
```

### 3. Install with Unraid template

Copy the template:

```bash
cp unraid-template.xml /boot/config/plugins/dockerMan/templates-user/openclaw-assistant.xml
```

If you built locally, edit the copied template and change:

```xml
<Repository>ghcr.io/emenblade/openclaw-assistant:latest</Repository>
```

to:

```xml
<Repository>openclaw-assistant:local</Repository>
```

Then in Unraid: **Docker → Add Container → openclaw-assistant**.

Fill in:

- Appdata path
- Obsidian vault root path
- Google credentials folder
- Gateway token (`openssl rand -hex 32`)
- OpenCode Zen API key
- Discord bot token
- Discord owner ID
- Optional Discord guild/channel IDs
- Assistant email
- Gmail app password
- Assistant calendar ID
- gog keyring password
- Timezone
- Owner name
- Assistant name
- Quiet hours

Leave **Privileged** off. Do not add `/var/run/docker.sock`.

### 4. Check startup

```bash
docker logs -f openclaw-assistant
```

On first boot the entrypoint:

- Creates `/home/node/.openclaw`
- Renders `openclaw.json` from env
- Copies starter prompts into the workspace
- Renders the Himalaya Gmail config
- Installs the official Discord plugin
- Adds the scoped `assistant-mail` executable to the exec allowlist
- Starts the Gateway

### 5. Open the Control UI

Browse to:

```text
http://UNRAID-IP:18789
```

Paste the Gateway token.

### 6. Headless Google OAuth

The container is headless, so use gog's remote/manual flow.

```bash
docker exec -it openclaw-assistant gog auth credentials /home/node/google/client_secret.json
docker exec -it openclaw-assistant gog auth keyring file
docker exec -it openclaw-assistant gog auth add assistant.you@gmail.com --services calendar --remote --step 1
```

Open the printed URL in a browser on your phone or laptop. Approve the Calendar scope. The final `localhost` redirect page may fail to load; copy the full URL from the browser address bar.

Then exchange it:

```bash
docker exec -it openclaw-assistant gog auth add assistant.you@gmail.com \
  --services calendar \
  --remote --step 2 \
  --auth-url 'PASTE_FULL_REDIRECT_URL_HERE'
```

Verify:

```bash
docker exec -it openclaw-assistant gog auth list
docker exec -it openclaw-assistant gog calendar list
```

> Google OAuth apps in Testing mode issue refresh tokens that expire after 7 days. In Google Cloud, publish the app to **Production** (an "unverified app" warning is acceptable for personal use) or use a service account instead.

### 7. Pair the phone and watch

1. Install **OpenClaw** from Google Play (`ai.openclaw.app`).
2. In the Control UI, go to **Devices → Pair device**.
3. Scan the setup code from the phone.
4. Approve the device.
5. Install the Wear OS companion on the Galaxy Watch 7.
6. Add the OpenClaw Tile to the watch.
7. Tap the Tile → Talk.

The watch uses the paired phone's connection. The phone must be nearby and connected to the NAS over WireGuard.

### 8. Test Discord

Send a DM to the new bot:

```text
hello
```

If it does not reply:

```bash
docker exec -it openclaw-assistant openclaw channels status --probe
docker exec -it openclaw-assistant openclaw pairing list discord
```

Approve the first pairing if needed:

```bash
docker exec -it openclaw-assistant openclaw pairing approve discord <CODE>
```

### 9. Test calendar and notes

```bash
docker exec -it openclaw-assistant assistant-mail calendar-list \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$(date -u -d '+7 days' +%Y-%m-%dT%H:%M:%SZ)"
```

Create a test event:

```bash
docker exec -it openclaw-assistant gog calendar create "$ASSISTANT_CALENDAR_ID" \
  --summary "OpenClaw test" \
  --from 2026-11-01T15:00:00Z \
  --to 2026-11-01T15:30:00Z \
  --description "Created by setup test"
```

Then ask the assistant in Discord:

```text
Note that the plumber quoted $450 and can come Tuesday.
```

Check the Obsidian `Assistant/Inbox` folder.

## Networking and TLS

This container is designed for **WireGuard-only** access:

- Publish port 18789 on the LAN.
- Do not port-forward it on your router.
- Access it only through WireGuard.

The OpenClaw Android app may show **Limited access** when connecting over plain `ws://` LAN. Chat and Talk normally still work; settings and upgrades may require a secure `wss://` endpoint. If you need full app access, add a reverse proxy with a real certificate later (Caddy/NPM/SWAG). That is optional for the first test.

Do not expose this container directly to the internet.

## Security

- Runs as UID/GID 1000, not root.
- `cap_drop: ALL`
- `no-new-privileges`
- No Docker socket.
- No host networking.
- Only the scoped `assistant-mail` command is allowlisted for the agent.
- No email send/delete/move wrapper command.
- Discord DM allowlist.
- Google Calendar scope only.
- Gmail app password limited to the dedicated assistant account.
- Do not put secrets in Git.

## Updating

Pin a version after the pilot. For now:

```bash
docker pull ghcr.io/emenblade/openclaw-assistant:latest
docker compose up -d
```

Back up appdata before updating. OpenClaw moves quickly; use `extended-stable` or a pinned tag after the pilot.

## Troubleshooting

### Container restarts or Gateway does not start

```bash
docker logs --tail 200 openclaw-assistant
docker exec -it openclaw-assistant openclaw doctor
docker exec -it openclaw-assistant openclaw config validate
```

### Discord plugin install failed

```bash
docker exec -it openclaw-assistant openclaw plugins install @openclaw/discord
docker restart openclaw-assistant
```

### Gmail auth fails

Check the app password and that 2FA/app passwords are enabled:

```bash
docker exec -it openclaw-assistant himalaya envelope list --account assistant
```

### Permission denied on appdata

```bash
chown -R 1000:1000 /mnt/cache/appdata/openclaw-assistant
```

### Obsidian notes not visible

The vault is mounted at:

```text
/home/node/.openclaw/workspace/obsidian
```

Confirm the host path is writable by UID 1000 and contains the `Assistant` folder.

### Calendar OAuth expired

If the app was in Testing mode, re-authorize or publish the app to Production. Testing-mode refresh tokens expire after 7 days.

## Known limitations

- No TLS by default; WireGuard-only. Full OpenClaw app settings may require `wss://`.
- No WhatsApp or Signal channel configured. Discord is the default.
- Email triage automation is not enabled by default; the wrapper is ready, but start with manual tests.
- No local LLM, Whisper, or TTS; phone/watch handles speech.
- The custom image is linux/amd64 only.

## License

MIT
