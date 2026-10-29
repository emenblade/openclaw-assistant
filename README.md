# OpenClaw Assistant for Unraid

A private, self-hosted personal assistant container:

- OpenClaw Gateway
- Discord bot for text and notifications
- OpenClaw Android/Wear OS app for voice/Talk
- Gmail IMAP/SMTP via Himalaya
- Google Calendar via a **service-account JSON key**
- Obsidian notes
- OpenCode Zen models
- WireGuard-only networking
- No Docker socket, no privileged mode
- No OAuth browser flow and no `gog` keyring

Designed for the user's Unraid NAS and Galaxy S25 + Galaxy Watch 7.

## Why OpenClaw

OpenClaw has the only official Android + Wear OS experience with a watch Tile/Talk and on-device speech. Hermes Agent is a strong alternative for memory/self-improvement, but it has no official Wear OS Tile/Talk equivalent.

## Requirements

- Unraid with Docker
- WireGuard access to the NAS
- 32 GB RAM is plenty; this container is capped at 1 GB RAM / 2 CPUs
- Dedicated Google account
- Google Cloud project with Calendar API and a **service account**
- Discord bot application (new bot, not an existing Red bot token)
- OpenCode Zen API key
- Obsidian vault path

## Model selection

The default is `opencode/claude-haiku-5-5`. You can set `PRIMARY_MODEL` in the template or `.env` to any OpenClaw model ref, for example:

- `opencode/claude-haiku-5-5` (recommended cheap default)
- `opencode/deepseek-v4.1-flash` (paid)
- `opencode/glm-5.3-flash` (paid, cheap)
- `opencode/gpt-6-luna` (paid, cheap)

Avoid `*-free` models for unattended automation. OpenClaw is not the OpenCode client, and free-tier routes may return `403 FreeTierError`.

If you change the model after first boot, use the OpenClaw Control UI or:

```bash
docker exec -it openclaw-assistant openclaw config set agents.defaults.model.primary "opencode/..."
docker restart openclaw-assistant
```

## Google setup: service account, not OAuth

This build does **not** use an OAuth client secret or a gog keyring. It uses a Google Cloud service-account key.

### 1. Create the service account

1. Open <https://console.cloud.google.com/>.
2. Create/select a project.
3. Enable **Google Calendar API**.
4. Go to **IAM & Admin → Service Accounts**.
5. Create a service account, e.g. `openclaw-calendar`.
6. Create a key: **Keys → Add key → Create new key → JSON**.
7. Download the JSON file.

The file must contain:

```json
{
  "type": "service_account",
  "client_email": "...iam.gserviceaccount.com",
  "private_key": "..."
}
```

An OAuth client `client_secret.json` will **not** work. It must say `"type": "service_account"`.

### 2. Put the key in appdata

Copy the JSON to:

```text
/mnt/cache/appdata/openclaw-assistant/google/service-account.json
```

This is a plain file in the container's data directory. You do not need to create anything inside the container.

### 3. Share the calendar with the service account

1. Open Google Calendar as the assistant account.
2. Open the `Assistant` calendar settings.
3. Share it with the service account email from the JSON (`client_email`).
4. Permission: **Make changes to events**.
5. Optionally share your main calendar with the same service-account email as **See all event details**.

No browser OAuth step is needed later.

## Quick start

### 1. Use the published image

```text
ghcr.io/emenblade/openclaw-assistant:latest
```

It is public. You do not need to build anything.

If you prefer building locally:

```bash
git clone https://github.com/emenblade/openclaw-assistant.git
cd openclaw-assistant
docker build -t openclaw-assistant:local .
```

### 2. Appdata and service account

You do **not** need to chown anything on the host. The container starts as root only long enough to create/chown the appdata tree to `PUID:PGID` (default `99:100`), then drops privileges.

Install the container first. It creates:

```text
/mnt/cache/appdata/openclaw-assistant/google/
```

Then put `service-account.json` in that folder and restart the container.

### 3. Install with the Unraid template

Copy the template:

```bash
cp OpenClaw-Butler.xml /boot/config/plugins/dockerMan/templates-user/OpenClaw-Butler.xml
```

If you built locally, change the copied template:

```xml
<Repository>openclaw-assistant:local</Repository>
```

Then in Unraid: **Docker → Add Container → openclaw-assistant**.

Fill in:

- Appdata path
- Obsidian vault root path
- PUID/PGID (leave `99`/`100` for Unraid unless your shares use different ownership)
- Gateway token (`openssl rand -hex 32`)
- OpenCode Zen API key
- Primary model (default `opencode/claude-haiku-5-5`)
- Discord bot token
- Discord owner ID
- Optional Discord guild/channel IDs
- Assistant email
- Gmail app password
- Assistant calendar ID
- Timezone
- Owner name
- Assistant name
- City / work hours / quiet hours

Leave **Privileged** off. Do not add `/var/run/docker.sock`.

### 4. Start it

Use the Unraid Docker UI. On first boot the entrypoint:

- Creates all internal directories
- Renders `openclaw.json` from env
- Seeds the prompts
- Renders the Himalaya Gmail config
- Installs the official Discord plugin
- Adds the scoped `assistant-mail` executable to the exec allowlist
- Checks Google Calendar access with the service account
- Starts the Gateway

View logs in the Unraid Docker UI. Look for:

```text
Google Calendar access OK.
Starting OpenClaw Gateway...
```

If calendar access fails, the calendar was not shared with the service-account email.

### 5. Open the Control UI

Browse to:

```text
http://UNRAID-IP:18789
```

Paste the Gateway token.

### 6. Pair the phone and watch

1. Install **OpenClaw** from Google Play (`ai.openclaw.app`).
2. In the Control UI, go to **Devices → Pair device**.
3. Scan the setup code from the phone.
4. Approve the device.
5. Install the Wear OS companion on the Galaxy Watch 7.
6. Add the OpenClaw Tile to the watch.
7. Tap the Tile → Talk.

The watch uses the paired phone's connection. The phone must be nearby and connected to the NAS over WireGuard.

### 7. Test from chat

No terminal commands are required. In Discord or the OpenClaw app:

```text
hello
what is on my calendar today?
create a 30-minute test event tomorrow at 3 PM
note that the plumber quoted $450 and can come Tuesday
what did I say about the plumber?
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

- Starts as root only to chown appdata, then drops to `PUID:PGID` (default `99:100`).
- Chowns only appdata and the Obsidian `Assistant` folder, not the whole vault.
- `cap_drop: ALL` plus only the capabilities needed for the drop (`CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`).
- `no-new-privileges`
- No Docker socket.
- No host networking.
- Only the scoped `assistant-mail` command is allowlisted for the agent.
- No email send/delete/move wrapper command.
- Discord DM allowlist.
- Google Calendar access is limited to calendars shared with the service account.
- Gmail app password limited to the dedicated assistant account.
- Do not put secrets in Git.

## Updating

Pin a version after the pilot. Update through the Unraid Docker UI or:

```bash
docker pull ghcr.io/emenblade/openclaw-assistant:latest
docker compose up -d
```

Back up appdata before updating. OpenClaw moves quickly; use `extended-stable` or a pinned tag after the pilot.

## Troubleshooting

### Container restarts or Gateway does not start

Use the Unraid Docker UI logs. If you want the CLI:

```bash
docker exec -it openclaw-assistant openclaw doctor
docker exec -it openclaw-assistant openclaw config validate
```

### Google Calendar access failed

- Confirm `/mnt/cache/appdata/openclaw-assistant/google/service-account.json` exists.
- Confirm it says `"type": "service_account"`.
- Confirm the Assistant calendar is shared with the `client_email` from that JSON as **Make changes to events**.
- Confirm the Calendar ID in the template matches the Assistant calendar.
- Restart the container.

### Discord plugin install failed

Open the Unraid Docker console or run:

```bash
docker exec -it openclaw-assistant openclaw plugins install @openclaw/discord
docker restart openclaw-assistant
```

### Gmail auth fails

Check the app password and that 2FA/app passwords are enabled. The container generates the Himalaya config on first boot.

### Permission denied on appdata

The container handles appdata ownership on startup. Confirm the host path is mapped to `/home/node/.openclaw` and that `PUID`/`PGID` match your Unraid shares (`99`/`100` by default).

### Obsidian notes not visible

The vault is mounted at:

```text
/home/node/obsidian
```

The entrypoint creates and chowns only `Assistant/`. Confirm the host path is readable by `PUID`/`PGID`; the assistant writes under `Assistant/`.

## Known limitations

- No TLS by default; WireGuard-only. Full OpenClaw app settings may require `wss://`.
- No WhatsApp or Signal channel configured. Discord is the default.
- Email triage automation is not enabled by default; the wrapper is ready, but start with manual tests.
- No local LLM, Whisper, or TTS; phone/watch handles speech.
- The custom image is linux/amd64 only.

## License

MIT
