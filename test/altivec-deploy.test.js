"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const deploy = require("../bin/altivec-deploy");

function temporaryDirectory(t) {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), "altivec-deploy-test-"),
  );
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

test("parseArgs preserves the legacy --yes timeout syntax", () => {
  const options = deploy.parseArgs([
    "build",
    "--device",
    "mac.local",
    "--yes",
    "15",
  ]);

  assert.equal(options.inputPath, path.resolve("build"));
  assert.equal(options.device, "mac.local");
  assert.equal(options.nonInteractive, true);
  assert.equal(options.timeout, 15);
});

test("parseArgs supports an explicit timeout", () => {
  const options = deploy.parseArgs([
    "build",
    "--device",
    "mac.local",
    "--timeout",
    "25",
    "--yes",
  ]);

  assert.equal(options.nonInteractive, true);
  assert.equal(options.timeout, 25);
});

test("parseArgs rejects missing option values", () => {
  assert.throws(
    () => deploy.parseArgs(["build", "--device"]),
    /requires a user@host/,
  );
  assert.throws(
    () => deploy.parseArgs(["build", "--timeout"]),
    /positive number/,
  );
});

test("parseArgs requires an SSH target", () => {
  assert.throws(
    () => deploy.parseArgs(["build", "--yes"]),
    /Missing required SSH target/,
  );
});

test("confirmation without a TTY requires --yes", () => {
  assert.throws(
    () =>
      deploy.requireConfirmationTerminal(
        { nonInteractive: false },
        { isTTY: false },
      ),
    /rerun with --yes/,
  );
  assert.doesNotThrow(() =>
    deploy.requireConfirmationTerminal(
      { nonInteractive: true },
      { isTTY: false },
    ),
  );
});

test("findAppBundles searches two levels and returns deterministic results", (t) => {
  const root = temporaryDirectory(t);
  fs.mkdirSync(path.join(root, "z", "Second.app"), { recursive: true });
  fs.mkdirSync(path.join(root, "a", "First.app"), { recursive: true });
  fs.mkdirSync(path.join(root, "too", "deep", "Ignored.app"), {
    recursive: true,
  });

  assert.deepEqual(deploy.findAppBundles(root), [
    path.join(root, "a", "First.app"),
    path.join(root, "z", "Second.app"),
  ]);
});

test("selectArtifact prefers the payload matching the app name", (t) => {
  const root = temporaryDirectory(t);
  fs.writeFileSync(path.join(root, "Old.zip"), "");
  fs.writeFileSync(path.join(root, "Current.zip"), "");

  assert.equal(
    deploy.selectArtifact(root, "Current", ".zip"),
    path.join(root, "Current.zip"),
  );
  assert.throws(
    () => deploy.selectArtifact(root, "Unknown", ".zip"),
    /Multiple/,
  );
});

test("findEnvFile walks upward no more than eight directories", (t) => {
  const root = temporaryDirectory(t);
  const nested = path.join(root, "one", "two", "three");
  fs.mkdirSync(nested, { recursive: true });
  fs.writeFileSync(path.join(root, ".env"), "TOKEN=value\n");

  assert.equal(deploy.findEnvFile(nested), path.join(root, ".env"));
  assert.equal(deploy.findEnvFile(nested, 2), null);
});

test("parseEnv accepts valid names and preserves values", () => {
  assert.deepEqual(
    deploy.parseEnv(
      "# comment\nTOKEN=hello world\n_BAD=x=y\nBAD-NAME=no\n  SPACE =kept\n",
    ),
    [
      ["TOKEN", "hello world"],
      ["_BAD", "x=y"],
      ["SPACE", "kept"],
    ],
  );
});

test("buildDebuggerInit escapes LLDB tokens", () => {
  const output = deploy.buildDebuggerInit(
    "settings set stop-disassembly-count 0\n",
    [["MESSAGE", 'hello "legacy" \\ mac']],
    "lldb",
    "/project/.env",
  );

  assert.match(output, /auto-injected from \/project\/\.env/);
  assert.match(output, /MESSAGE=hello \\"legacy\\" \\\\ mac/);
});

test("parseProbeOutput retains values containing equals signs", () => {
  const values = deploy.parseProbeOutput(
    "UNAME=Darwin\nHOME=/Users/a=b\nGDB=\n",
  );

  assert.equal(values.get("UNAME"), "Darwin");
  assert.equal(values.get("HOME"), "/Users/a=b");
  assert.equal(values.get("GDB"), "");
});

test("validatePlan rejects incompatible targets before deployment", () => {
  const app = { directory: "/build", ipaPath: null, zipPath: null };
  assert.throws(
    () => deploy.validatePlan(app, { type: "linux", os: "linux" }),
    /Unable to deploy/,
  );
  assert.throws(
    () =>
      deploy.validatePlan(app, {
        type: "mac",
        os: "Darwin",
        home: "/Users/test",
      }),
    /requires a \.zip payload/,
  );
});

test("shellQuote safely quotes apostrophes", () => {
  assert.equal(deploy.shellQuote("it's ready"), `'it'"'"'s ready'`);
});
