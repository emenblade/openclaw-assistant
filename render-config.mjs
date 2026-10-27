#!/usr/bin/env node
// Render the strict JSON config template with environment variables.
// This intentionally does not parse JSON5; the template is plain JSON.
import fs from "node:fs";

const [, , templatePath, outputPath] = process.argv;
if (!templatePath || !outputPath) {
  console.error("usage: render-config.mjs <template.json> <output.json>");
  process.exit(2);
}

const replace = (value) =>
  value.replace(/\$\{([A-Z0-9_]+)\}/g, (_, key) => process.env[key] ?? "");

const raw = replace(fs.readFileSync(templatePath, "utf8"));
let config;
try {
  config = JSON.parse(raw);
} catch (error) {
  console.error(`Invalid rendered JSON: ${error.message}`);
  process.exit(1);
}

// Discord is optional. Disable it unless the token/owner IDs are present and
// the entrypoint successfully installed the plugin.
const discordEnabled =
  process.env.DISCORD_ENABLED === "true" &&
  Boolean(process.env.DISCORD_BOT_TOKEN) &&
  Boolean(process.env.DISCORD_OWNER_ID);

if (!discordEnabled) {
  config.channels.discord.enabled = false;
  delete config.channels.discord.token;
  delete config.channels.discord.allowFrom;
} else {
  config.channels.discord.enabled = true;
  config.channels.discord.token = process.env.DISCORD_BOT_TOKEN;
  config.channels.discord.allowFrom = [process.env.DISCORD_OWNER_ID];

  // Optional guild/channel allowlist for a dedicated private server.
  if (process.env.DISCORD_GUILD_ID) {
    const guild = { requireMention: false };
    if (process.env.DISCORD_CHANNEL_ID) {
      guild.channels = {
        [process.env.DISCORD_CHANNEL_ID]: { requireMention: false },
      };
    }
    config.channels.discord.guilds = {
      [process.env.DISCORD_GUILD_ID]: guild,
    };
  }
}

fs.writeFileSync(outputPath, `${JSON.stringify(config, null, 2)}\n`, {
  mode: 0o600,
});
console.log(`Rendered ${outputPath}`);
