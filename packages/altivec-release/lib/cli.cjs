'use strict';
const { spawnSync } = require('node:child_process');
const P = require('./project.cjs');
const R = require('./release.cjs');
const A = require('./artifacts.cjs');
const { fs, path, fail, atomic } = P;
const packageVersion = require('../package.json').version;
const usage = {
  doctor: 'doctor [--json] [--check-remote]\nReport checkout, identity, detached HEAD, dirty files and remote separately.\nOffline by default; --check-remote explicitly contacts origin for the release tag.',
  current: 'current [--json]\nRead the configured version without Git, SDKs or credentials.',
  prepare: 'prepare [major|minor|patch] [--set VERSION] [--new-plan] [--dry-run]\nValidate and update version files; save build/release/plan.json without invoking Git.\nRepeated prepare resumes the plan. Use --new-plan only after the prior commit/tag.\nReview on the host, then commit. Never implicitly commits or pushes.',
  set: 'set VERSION [--dry-run]\nSet the version and save a recoverable preparation plan; no Git required.',
  bump: 'bump [major|minor|patch] [--set VERSION] [--no-push]\nDeprecated local preparation alias. Never commits, tags, or pushes. Use prepare.',
  check: 'check VERSION [--json]\nValidate all configured version strings without Git.',
  'ci-env': 'ci-env [TAG] [--github-env PATH] [--json]\nValidate TAG (or GITHUB_REF_NAME) and emit RELEASE_TAG and RELEASE_VERSION.',
  build: 'build [--target NAME ...] [--dry-run]\nRun configured build actions, usually in Docker. No Git configuration required.',
  stage: 'stage [VERSION] [--target NAME ...] [--dist DIRECTORY] [--dry-run]\nCopy artifacts and write build/release/artifact-manifest.json. No Git staging.\nNew default: build/release/artifacts. Migrated configurations retain dist.',
  commit: 'commit [--name NAME --email EMAIL] [--dry-run]\nOn the host: verify the plan, version files, branch, staged files and local tag;\ncommit only plan files and create a local tag. Reads existing Git identity.\nRetries resume commit/tag after a failure. Never pushes or checks the network.',
  push: 'push [--dry-run]\nExplicitly publish the prepared commit and tag to origin from the host.\nRetry after partial failure; never prepare a second bump. Dry-run is offline.',
  migrate: 'migrate [--config OLD.yml] [--output NEW.json] [--dry-run]\nOne-time YAML-to-JSON conversion using Python/PyYAML (available in the image).\nPreserves shell commands, targets, artifacts and dist staging. Never overwrites.',
};
function help(command) {
  if (command && usage[command]) return `altivec-release ${usage[command]}\n\nCommon: --help, --version, --config FILE, --dry-run\nInspection: doctor/current/check/ci-env support --json.\n`;
  return `altivec-release ${packageVersion} — local-first releases\n\nUsage: altivec-release COMMAND [options]\nCommands: ${Object.keys(usage).join(', ')}\nCommon: --help, --version, --config FILE, --dry-run\nInspection: --json (doctor, current, check, ci-env)\n\nInside Docker / a source export (no Git identity, keys, or .git needed):\n  altivec-release doctor\n  altivec-release current\n  altivec-release prepare patch --dry-run\n  altivec-release prepare patch\n  altivec-release build --target iOS\n  altivec-release stage\nOn the host checkout, after reviewing changes:\n  altivec-release commit\nOnly when publication is explicitly wanted:\n  altivec-release push\n\nRun altivec-release COMMAND --help for details. Node >=22; no npm dependencies.\n`;
}
function parse(args) {
  const opts = { target: [] }, positional = [];
  const values = new Set(['config', 'target', 'set', 'name', 'email', 'dist', 'github-env', 'output']);
  const flags = new Set(['help', 'version', 'dry-run', 'json', 'check-remote', 'no-push', 'new-plan']);
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '-h') { opts.help = true; continue; }
    if (!args[i].startsWith('-')) { positional.push(args[i]); continue; }
    const match = /^--([^=]+)(?:=(.*))?$/.exec(args[i]);
    if (!match) fail(`unknown option: ${args[i]}`);
    const [, key, inline] = match;
    if (values.has(key)) {
      const value = inline === undefined ? args[++i] : inline;
      if (!value || value.startsWith('--')) fail(`--${key} needs a value`);
      if (key === 'target') opts.target.push(value);
      else opts[key] = value;
    } else if (flags.has(key) && inline === undefined) opts[key] = true;
    else fail(`unknown option: ${args[i]}`);
  }
  return { opts, positional };
}
function output(value, opts) {
  if (opts.json) console.log(JSON.stringify(value));
  else if (typeof value === 'string') console.log(value);
  else for (const [key, item] of Object.entries(value)) console.log(`${key}: ${typeof item === 'string' ? item : JSON.stringify(item)}`);
}
function migrate(opts) {
  const source = opts.config ? path.resolve(opts.config) : P.find();
  if (!source || !/\.ya?ml$/i.test(source)) fail('migrate needs --config path/to/.altivec-release.yml');
  const destination = path.resolve(opts.output || source.replace(/\.ya?ml$/i, '.json'));
  if (fs.existsSync(destination)) fail(`migration destination already exists: ${destination}`);
  const result = spawnSync('python3', [path.join(__dirname, 'migrate.py'), source], { encoding: 'utf8' });
  if (result.error || result.status !== 0) fail(result.stderr.trim() || result.error?.message || 'migration failed');
  const converted = JSON.parse(result.stdout);
  // Validate with the real loader relative to the original project paths.
  // A dry run must not create a temporary file in the source tree.
  if (path.dirname(destination) !== path.dirname(source)) fail('migration output must be beside the YAML config so relative paths retain their meaning');
  P.load(destination, converted);
  if (!opts['dry-run']) atomic(destination, JSON.stringify(converted, null, 2) + '\n');
  return { destination, dryRun: !!opts['dry-run'], config: converted, next: 'Review the JSON, update workflow references, and remove the old YAML when ready. JSON takes precedence. Migrated stage_dir remains dist.' };
}
function main(args = process.argv.slice(2)) {
  try {
    const { opts, positional } = parse(args);
    const command = positional.shift();
    if (opts.version) { console.log(packageVersion); return; }
    if (opts.help || !command) { console.log(help(command)); return; }
    if (!usage[command]) fail(`unknown command: ${command}; run altivec-release --help`);
    const allowed = {
      doctor: ['check-remote', 'json'], current: ['json'], check: ['json'],
      prepare: ['set', 'new-plan'], bump: ['set', 'no-push', 'new-plan'], set: ['new-plan'],
      commit: ['name', 'email'], push: [], build: ['target'], stage: ['target', 'dist'],
      'ci-env': ['github-env', 'json'], migrate: ['output'],
    };
    for (const key of Object.keys(opts)) {
      if (key === 'target' && !opts.target.length) continue;
      if (!['help', 'version', 'dry-run', 'config', ...allowed[command]].includes(key)) fail(`--${key} is not supported by ${command}`);
    }
    if (positional.length > (['prepare', 'bump', 'set', 'check', 'stage', 'ci-env'].includes(command) ? 1 : 0)) fail(`too many arguments for ${command}`);
    if (command === 'migrate') { output(migrate(opts), opts); return; }
    const file = opts.config ? path.resolve(opts.config) : P.find();
    if (command === 'doctor') {
      let c = null, configError;
      if (file) { try { c = P.load(file); } catch (error) { configError = error.message; } }
      output({ ...R.doctor(c, opts), ...(configError ? { configError } : {}) }, opts); return;
    }
    const c = P.load(file), value = positional[0];
    if (command === 'current') { output(opts.json ? { version: P.current(c) } : P.current(c), opts); return; }
    if (command === 'check') { P.check(c, value); output({ version: value, valid: true }, opts); return; }
    if (command === 'ci-env') {
      const tag = value || process.env.GITHUB_REF_NAME;
      if (!tag) fail('ci-env needs a tag or GITHUB_REF_NAME');
      const version = tag.startsWith(c.prefix) ? tag.slice(c.prefix.length) : tag;
      P.check(c, version);
      const env = { RELEASE_TAG: tag, RELEASE_VERSION: version };
      const lines = Object.entries(env).map(([key, val]) => `${key}=${val}`).join('\n') + '\n';
      if (opts['github-env'] && !opts['dry-run']) fs.appendFileSync(opts['github-env'], lines);
      if (opts.json) output(env, opts); else process.stdout.write(lines);
      return;
    }
    if (command === 'build') { A.build(c, opts); return; }
    const action = () => {
      if (command === 'stage') return A.stage(c, opts, value);
      if (command === 'commit') return R.commit(c, opts);
      if (command === 'push') return R.push(c, opts);
      if (command === 'bump') console.error('bump is a deprecated local preparation alias. It never commits/tags/pushes; use prepare, then commit on the host.');
      if (command === 'set') { opts.set = P.version(value); opts.allowSame = true; }
      return R.prepare(c, opts, value);
    };
    output(opts['dry-run'] ? action() : R.withLock(c, action), opts);
  } catch (error) {
    console.error(`altivec-release: ${error.message}`);
    process.exitCode = 1;
  }
}
module.exports = { main };
