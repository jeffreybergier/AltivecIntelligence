#!/usr/bin/env node
"use strict";
const fs = require("node:fs"),
  path = require("node:path");
const { catalog, generate } = require("../lib/generate.cjs");
const version = require("../package.json").version;
const help = `altivec-app ${version} — offline project templates

  altivec-app templates [--json]
  altivec-app new --template cocoa-shared --name MyApp \\
    --bundle-id com.example.myapp --destination ./MyApp
  altivec-app new --help
  altivec-app assets --project . [--source icon.png]

new options:
  --platform macOS,iOS    Select a subset of the template's platforms
  --mac-archs full|legacy|arm64|x86_64
  --ios-package ipa|zip|deb-rootful|deb-rootless (template-dependent)
  --dry-run              List generated files without creating anything
  --json                 Machine-readable result

No destination is overwritten. Generation is offline; Python 3 validates plists.
Artwork replacement alone needs ImageMagick. Build SDKs are not needed for help,
template discovery, generation or portable tests. iOS artwork is phone portrait.
Use altivec-sdk for SDK installation. Old iPhones retain the shell generator.
`;
try {
  const args = process.argv.slice(2);
  if (!args.length || args.includes("--help") || args.includes("-h")) {
    console.log(help);
    process.exit(0);
  }
  if (args[0] === "--version") {
    console.log(version);
    process.exit(0);
  }
  const command = args.shift(),
    o = {};
  const allowed = {
    new: [
      "template",
      "name",
      "bundle-id",
      "destination",
      "platform",
      "mac-archs",
      "ios-package",
      "dry-run",
      "json",
    ],
    templates: ["json"],
    assets: ["project", "source"],
  }[command];
  if (!allowed) throw Error(`Unknown command: ${command}`);
  while (args.length) {
    const key = args.shift().replace(/^--/, "");
    if (!allowed.includes(key) || Object.hasOwn(o, key))
      throw Error(`Unknown or duplicate option: ${key}`);
    if (["dry-run", "json"].includes(key)) o[key] = true;
    else {
      const value = args.shift();
      if (!value || value.startsWith("--"))
        throw Error(`--${key} requires a value`);
      o[key] = value;
    }
  }
  let result;
  if (command === "templates") result = catalog;
  if (command === "new") result = generate(o);
  if (command === "assets") {
    if (!o.project) throw Error("assets requires --project");
    const project = path.resolve(o.project);
    if (!fs.existsSync(path.join(project, ".altivec-template.json")))
      throw Error("Not an altivec-app project");
    require("../lib/assets.cjs").generate(project, o.source);
    require("../lib/assets.cjs").validate(project);
    result = { project, artwork: "updated" };
  }
  if (o.json || o["dry-run"]) console.log(JSON.stringify(result, null, 2));
  else if (command === "templates")
    for (const t of catalog.templates)
      console.log(
        `${t.id}: ${t.description}\n  ${t.platforms.join(", ")}; ${t.privilege}`,
      );
  else if (command === "new")
    console.log(
      `Created ${result.template} at ${result.destination}\nNext: cd ${result.destination} && make test-host`,
    );
  else console.log(JSON.stringify(result, null, 2));
} catch (e) {
  console.error(`error: ${e.message}`);
  process.exitCode = 1;
}
