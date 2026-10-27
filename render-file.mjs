#!/usr/bin/env node
// Render a text template with ${ENV_VAR} placeholders.
import fs from "node:fs";

const [, , inputPath, outputPath] = process.argv;
if (!inputPath || !outputPath) {
  console.error("usage: render-file.mjs <input> <output>");
  process.exit(2);
}

const template = fs.readFileSync(inputPath, "utf8");
const rendered = template
  .replace(/\$\{([A-Z0-9_]+)\}/g, (_, key) => process.env[key] ?? "")
  .replace(/\{\{([A-Z0-9_]+)\}\}/g, (_, key) => process.env[key] ?? "");
fs.writeFileSync(outputPath, rendered);
console.log(`Rendered ${outputPath}`);
