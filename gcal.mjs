#!/usr/bin/env node
// Minimal Google Calendar CLI using a service-account JSON key.
// No OAuth browser flow, no gog keyring, no external npm dependencies.
//
// Env:
//   GOOGLE_SERVICE_ACCOUNT_JSON  default /home/node/google/service-account.json
//   ASSISTANT_CALENDAR_ID        required
//   TZ                           fallback timezone
//
// Commands:
//   gcal list --from <iso> --to <iso>
//   gcal create <json-file>
//   gcal delete <event-id>

import crypto from "node:crypto";
import fs from "node:fs";

const SA_PATH =
  process.env.GOOGLE_SERVICE_ACCOUNT_JSON ||
  "/home/node/google/service-account.json";
const CALENDAR_ID = process.env.ASSISTANT_CALENDAR_ID || "";
const SCOPE = "https://www.googleapis.com/auth/calendar";
const API = process.env.GCAL_API_BASE || "https://www.googleapis.com/calendar/v3";

function fail(message, code = 1) {
  console.error(JSON.stringify({ ok: false, error: message }));
  process.exit(code);
}

function b64url(value) {
  return Buffer.from(value)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function readServiceAccount() {
  if (!fs.existsSync(SA_PATH)) {
    fail(`Service account JSON not found: ${SA_PATH}`);
  }
  let sa;
  try {
    sa = JSON.parse(fs.readFileSync(SA_PATH, "utf8"));
  } catch (error) {
    fail(`Cannot parse service account JSON: ${error.message}`);
  }
  if (sa.type !== "service_account" || !sa.client_email || !sa.private_key) {
    fail(
      "File is not a service-account key. It must contain type=service_account, client_email, and private_key. An OAuth client_secret.json will not work.",
    );
  }
  return sa;
}

async function getAccessToken(sa) {
  const now = Math.floor(Date.now() / 1000);
  const tokenUri = sa.token_uri || "https://oauth2.googleapis.com/token";
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: SCOPE,
      aud: tokenUri,
      iat: now,
      exp: now + 3600,
    }),
  );
  const signingInput = `${header}.${payload}`;
  const signer = crypto.createSign("RSA-SHA256");
  signer.update(signingInput);
  const signature = signer.sign(sa.private_key, "base64url");
  const assertion = `${signingInput}.${signature}`;

  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.access_token) {
    fail(
      `Google token exchange failed: ${response.status} ${
        body.error_description || body.error || "unknown error"
      }`,
    );
  }
  return body.access_token;
}

async function api(token, path, options = {}) {
  const response = await fetch(`${API}${path}`, {
    ...options,
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      ...(options.headers || {}),
    },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    fail(
      `Calendar API failed: ${response.status} ${
        body.error?.message || JSON.stringify(body)
      }`,
    );
  }
  return body;
}

function calPath(suffix = "") {
  if (!CALENDAR_ID) fail("ASSISTANT_CALENDAR_ID is required");
  return `/calendars/${encodeURIComponent(CALENDAR_ID)}${suffix}`;
}

function normalizeEvent(event) {
  return {
    id: event.id,
    summary: event.summary || "(no title)",
    start: event.start?.dateTime || event.start?.date || null,
    end: event.end?.dateTime || event.end?.date || null,
    location: event.location || null,
    htmlLink: event.htmlLink || null,
  };
}

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const item = argv[i];
    if (item.startsWith("--")) {
      const key = item.slice(2);
      const value = argv[i + 1];
      if (!value || value.startsWith("--")) {
        args[key] = true;
      } else {
        args[key] = value;
        i++;
      }
    } else {
      args._.push(item);
    }
  }
  return args;
}

function readPayload(path) {
  const raw = path && path !== "-" ? fs.readFileSync(path, "utf8") : fs.readFileSync(0, "utf8");
  try {
    return JSON.parse(raw);
  } catch (error) {
    fail(`Invalid JSON payload: ${error.message}`);
  }
}

const [, , command, ...rest] = process.argv;
const args = parseArgs(rest);

if (!["list", "create", "delete"].includes(command)) {
  fail("Usage: gcal list --from <iso> --to <iso> | gcal create <json-file> | gcal delete <event-id>", 2);
}

const sa = readServiceAccount();
const token = await getAccessToken(sa);

if (command === "list") {
  if (!args.from || !args.to) fail("list requires --from and --to");
  const params = new URLSearchParams({
    timeMin: args.from,
    timeMax: args.to,
    singleEvents: "true",
    orderBy: "startTime",
    maxResults: "100",
    showDeleted: "false",
  });
  const data = await api(token, `${calPath("/events")}?${params.toString()}`);
  console.log(
    JSON.stringify(
      { ok: true, events: (data.items || []).map(normalizeEvent) },
      null,
      2,
    ),
  );
  process.exit(0);
}

if (command === "delete") {
  if (!args._[0]) fail("delete requires an event id");
  await api(token, calPath(`/events/${encodeURIComponent(args._[0])}`), {
    method: "DELETE",
  });
  console.log(JSON.stringify({ ok: true, deleted: args._[0] }));
  process.exit(0);
}

if (command === "create") {
  const payload = readPayload(args._[0]);
  const summary = String(payload.summary || "").trim();
  const from = payload.from;
  const to = payload.to;
  if (!summary || !from || !to) fail("create requires summary, from, and to");

  const timezone = payload.timezone || process.env.TZ || "UTC";
  const allDay = Boolean(payload.all_day);
  const event = {
    summary,
    start: allDay ? { date: String(from).slice(0, 10) } : { dateTime: from, timeZone: timezone },
    end: allDay ? { date: String(to).slice(0, 10) } : { dateTime: to, timeZone: timezone },
  };
  if (payload.description) event.description = String(payload.description);
  if (payload.location) event.location = String(payload.location);
  if (payload.source_message_id) {
    event.extendedProperties = {
      private: { sourceMessageId: String(payload.source_message_id) },
    };
  }
  if (Array.isArray(payload.attendees) && payload.attendees.length) {
    event.attendees = payload.attendees.map((email) => ({ email }));
  }

  const data = await api(token, `${calPath("/events")}?sendUpdates=none`, {
    method: "POST",
    body: JSON.stringify(event),
  });
  console.log(JSON.stringify({ ok: true, event: normalizeEvent(data) }, null, 2));
  process.exit(0);
}
