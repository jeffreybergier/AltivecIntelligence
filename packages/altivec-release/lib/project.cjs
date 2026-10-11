'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const plist = require('./plist.cjs');
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
const fail = message => { throw new Error(message); };
const read = file => fs.readFileSync(file);
const json = file => JSON.parse(read(file));
function version(value) {
  if (typeof value !== 'string' || !/^\d+(?:\.\d+){0,2}$/.test(value) || value.split('.').some(x => !Number.isSafeInteger(Number(x)))) {
    fail('version must be numeric dot-separated, e.g. 1, 1.0, or 1.0.3');
  }
  return value;
}
function bump(value, part) {
  const parts = version(value).split('.').map(Number);
  while (parts.length < 3) parts.push(0);
  const index = ['major', 'minor', 'patch'].indexOf(part);
  if (index < 0) fail('prepare expects major, minor, patch, or --set VERSION');
  parts[index]++;
  parts.fill(0, index + 1);
  return version(parts.join('.'));
}
function safe(root, name) {
  if (typeof name !== 'string' || !name || name.includes('\0')) fail('expected a nonempty project path');
  const file = path.resolve(root, name), relative = path.relative(root, file);
  if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative) || relative.split(path.sep).some(part => part.toLowerCase() === '.git')) {
    fail(`path must stay inside the project and outside .git: ${name}`);
  }
  let current = root;
  for (const part of relative.split(path.sep).filter(Boolean)) {
    current = path.join(current, part);
    try {
      if (fs.lstatSync(current).isSymbolicLink()) fail(`symlink paths are unsupported: ${name}`);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
  return file;
}
function atomic(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${crypto.randomUUID()}.tmp`;
  try {
    fs.writeFileSync(temp, data, { flag: 'wx', mode: fs.existsSync(file) ? fs.statSync(file).mode : 0o644 });
    fs.renameSync(temp, file);
  } finally { fs.rmSync(temp, { force: true }); }
}
function strings(value, label, fallback = []) {
  if (value === undefined) return fallback;
  const result = typeof value === 'string' ? [value] : value;
  if (!Array.isArray(result) || result.some(x => typeof x !== 'string' || !x)) fail(`${label} must be a string or array of nonempty strings`);
  return result;
}
function find(start = process.cwd()) {
  let current = path.resolve(start);
  while (true) {
    for (const name of ['.altivec-release.json', 'altivec-release.json', '.altivec-release.yml', 'altivec-release.yml']) {
      if (fs.existsSync(path.join(current, name))) return path.join(current, name);
    }
    if (path.dirname(current) === current) return null;
    current = path.dirname(current);
  }
}
function load(file, suppliedData) {
  if (!file) fail('release config not found; copy templates/altivec-release.json to .altivec-release.json');
  if (/\.ya?ml$/i.test(file)) fail(`YAML needs a one-time migration: altivec-release migrate --config ${JSON.stringify(file)} (Python/PyYAML required only for migration)`);
  file = suppliedData ? path.resolve(file) : fs.realpathSync(file);
  const data = suppliedData || json(file), root = path.dirname(file);
  if (data.schema_version !== 1) fail('release config requires schema_version: 1');
  if (!data.version || typeof data.version !== 'object') fail('version must be an object');
  const source = safe(root, data.version.source);
  const format = data.version.format || 'plist';
  if (!['plist', 'text'].includes(format)) fail('version.format must be plist or text');
  const keys = strings(data.version.keys, 'version.keys', ['CFBundleShortVersionString', 'CFBundleVersion']);
  const sourceKey = data.version.source_key || keys[0];
  if (typeof sourceKey !== 'string') fail('version.source_key must be a string');
  const items = data.version.plists ?? (format === 'plist' ? [data.version.source] : []);
  if (!Array.isArray(items)) fail('version.plists must be an array');
  const plists = items.map(item => ({
    file: safe(root, typeof item === 'string' ? item : item.path),
    keys: strings(typeof item === 'string' ? undefined : item.keys, 'plist keys', keys),
  }));
  if (plists.some(p => !p.keys.length || new Set(p.keys).size !== p.keys.length) || new Set(plists.map(p => p.file)).size !== plists.length) fail('duplicate plist paths/keys or empty key list');
  if (format === 'plist' && !plists.some(p => p.file === source && p.keys.includes(sourceKey))) fail('version.plists must include the version source and source_key');
  if (format === 'text' && plists.some(p => p.file === source)) fail('text version source cannot also be a plist');
  const files = [...new Set([source, ...plists.map(p => p.file), ...strings(data.versioned_files, 'versioned_files').map(p => safe(root, p))])];
  if (files.some(p => p === file || p === root || path.relative(root, p).startsWith(`build${path.sep}release${path.sep}`))) fail('version files cannot include configuration or release state');
  const appName = data.app_name || data.name || path.basename(root);
  const prefix = data.tag_prefix ?? 'v';
  if (typeof appName !== 'string' || typeof prefix !== 'string' || !/^[A-Za-z0-9._/-]*$/.test(prefix) || prefix.includes('..') || prefix.startsWith('/') || prefix.startsWith('-') || prefix.includes('//') || prefix.split('/').some(part => part.startsWith('.') || part.endsWith('.lock'))) fail('invalid app_name or tag_prefix');
  const message = data.release?.commit_message || 'chore(release): release {version}';
  if (typeof message !== 'string') fail('release.commit_message must be a string');
  const targets = (data.targets || []).map(t => {
    if (!t.name || typeof t.name !== 'string') fail('target name is required');
    if (t.artifacts && (t.artifact || t.asset_name)) fail('cannot mix artifacts with artifact/asset_name');
    if (!Array.isArray(t.build || [])) fail('build must be an array of {exec,args} or {shell} actions');
    const actions = (t.build || []).map(action => {
      if (action && typeof action.shell === 'string' && Object.keys(action).length === 1) return action;
      if (action && typeof action.exec === 'string' && action.exec && Array.isArray(action.args ?? []) && (action.args || []).every(a => typeof a === 'string') && Object.keys(action).every(k => ['exec', 'args'].includes(k))) return { exec: action.exec, args: action.args || [] };
      fail('build actions require {"exec":"make","args":["release"]} or explicit {"shell":"..."}; migrate old YAML first');
    });
    const items = t.artifacts ?? (t.artifact ? [{ path: t.artifact, asset_name: t.asset_name }] : []);
    if (!Array.isArray(items)) fail('artifacts must be an array');
    return { name: t.name, workdir: safe(root, t.workdir || '.'), actions, artifacts: items.map(a => ({
      file: safe(root, typeof a === 'string' ? a : a.path),
      template: typeof a === 'string' ? undefined : a.asset_name,
    })) };
  });
  if (new Set(targets.map(t => t.name)).size !== targets.length) fail('duplicate target name');
  return { root, file, data, source, sourceKey, format, plists, files, appName, prefix, message, targets, configHash: hash(suppliedData ? JSON.stringify(suppliedData) : read(file)) };
}
function text(file) {
  const bytes = read(file);
  try { return new TextDecoder('utf-8', { fatal: true }).decode(bytes); }
  catch { fail(`unsupported format in ${file}; use UTF-8 text/XML, not binary plists`); }
}
function current(c) {
  return version(c.format === 'text' ? text(c.source).trim() : plist.inspect(text(c.source), [c.sourceKey]).values[0]);
}
function check(c, value) {
  version(value);
  if (current(c) !== value) fail(`version source differs from ${value}`);
  for (const p of c.plists) {
    if (plist.inspect(text(p.file), p.keys).values.some(v => v !== value)) fail(`version mismatch in ${path.relative(c.root, p.file)}; expected ${value}`);
  }
}
function edits(c, value) {
  version(value);
  const result = new Map(c.files.map(file => [file, read(file)]));
  if (c.format === 'text') result.set(c.source, Buffer.from(`${value}\n`));
  for (const p of c.plists) {
    const parsed = plist.inspect(text(p.file), p.keys, value);
    parsed.values.forEach(version);
    result.set(p.file, Buffer.from(parsed.updated));
  }
  return [...result].map(([file, after]) => {
    const before = read(file);
    return { path: path.relative(c.root, file), before: before.toString('base64'), after: after.toString('base64'), beforeHash: hash(before), afterHash: hash(after) };
  });
}
function format(template, c, value, target = '') {
  if (typeof template !== 'string') fail('template must be a string');
  const values = { app_name: c.appName, version: value, tag: c.prefix + value, target };
  return template.replace(/\{([^{}]+)\}/g, (_, key) => key in values ? values[key] : fail(`unknown template field: ${key}`));
}
module.exports = { fs, path, hash, fail, read, json, version, bump, safe, atomic, find, load, current, check, edits, format };
