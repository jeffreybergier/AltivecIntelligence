'use strict';
const { spawnSync } = require('node:child_process');
const P = require('./project.cjs');
const { fs, path, safe, fail, read, hash, atomic } = P;
function targets(c, names) {
  if (!c.targets.length) fail('no targets configured');
  const selected = names.length ? names.map(name => c.targets.find(t => t.name === name) || fail(`unknown release target: ${name}`)) : c.targets;
  return [...new Set(selected)];
}
function build(c, opts) {
  const selected = targets(c, opts.target);
  for (const t of selected) if (!t.actions.length || !fs.statSync(t.workdir).isDirectory()) fail(`target ${t.name} needs build commands and an existing workdir`);
  for (const t of selected) {
    for (const action of t.actions) {
      console.log(`--- ${t.name}: ${JSON.stringify(action)} (in ${path.relative(c.root, t.workdir) || '.'}) ---`);
      if (opts['dry-run']) continue;
      const result = action.shell !== undefined ? spawnSync('/bin/sh', ['-c', action.shell], { cwd: t.workdir, stdio: 'inherit' }) : spawnSync(action.exec, action.args, { cwd: t.workdir, stdio: 'inherit' });
      if (result.error || result.status !== 0) fail(`build failed for ${t.name}: ${result.error?.message || `exit ${result.status}`}`);
    }
  }
}
function inventory(file, relative = '') {
  const stat = fs.lstatSync(file);
  if (stat.isSymbolicLink() || (!stat.isDirectory() && !stat.isFile())) fail(`unsupported artifact entry: ${file}; archive symlink-containing bundles first`);
  if (stat.isFile()) return [{ path: relative, sha256: hash(read(file)), mode: stat.mode & 0o777 }];
  return [{ path: relative + '/', directory: true }, ...fs.readdirSync(file).sort().flatMap(name => inventory(path.join(file, name), relative ? `${relative}/${name}` : name))];
}
const overlaps = (a, b) => a === b || a.startsWith(b + path.sep) || b.startsWith(a + path.sep);
function stage(c, opts, version) {
  const value = P.version(version || P.current(c));
  P.check(c, value);
  const dist = safe(c.root, opts.dist || c.data.stage_dir || 'build/release/artifacts');
  const manifestFile = safe(c.root, 'build/release/artifact-manifest.json');
  const reserved = [c.file, ...c.files, safe(c.root, 'build/release/plan.json'), safe(c.root, 'build/release/history'), safe(c.root, 'build/release/.lock'), manifestFile];
  if (reserved.some(file => overlaps(file, dist))) fail('staging directory overlaps source/configuration or release state');
  const entries = targets(c, opts.target).flatMap(t => {
    if (!t.artifacts.length) fail(`target ${t.name} has no artifacts`);
    return t.artifacts.map(a => {
      const name = P.format(a.template || path.basename(a.file), c, value, t.name);
      if (!name || name === '.' || name === '..' || /[/\\\x00-\x1f]/.test(name)) fail(`invalid asset name: ${name}`);
      const destination = safe(c.root, path.join(dist, name));
      const contents = inventory(a.file); // Check every input before copying any.
      return { target: t.name, source: path.relative(c.root, a.file), asset: name, destination: path.relative(c.root, destination), sha256: fs.statSync(a.file).isFile() ? contents[0].sha256 : hash(JSON.stringify(contents)), contents };
    });
  });
  if (new Set(entries.map(e => e.asset.toLowerCase())).size !== entries.length) fail('duplicate asset names');
  for (const entry of entries) {
    const dest = safe(c.root, entry.destination);
    if (entries.some(e => overlaps(dest, safe(c.root, e.source)))) fail('artifact destination overlaps a source artifact');
    if (fs.existsSync(dest)) inventory(dest); // Never traverse destination symlinks.
  }
  const manifest = { schema_version: 1, version: value, tag: c.prefix + value, configSha256: c.configHash, provenance: process.env.GITHUB_SHA ? { githubSha: process.env.GITHUB_SHA } : null, artifacts: entries };
  if (!opts['dry-run']) {
    fs.mkdirSync(dist, { recursive: true });
    for (const entry of entries) {
      const dest = safe(c.root, entry.destination), source = safe(c.root, entry.source);
      if (fs.statSync(source).isFile()) {
        atomic(dest, read(source));
        fs.chmodSync(dest, fs.statSync(source).mode & 0o777);
      }
      else {
        const temp = fs.mkdtempSync(path.join(dist, '.stage-'));
        try {
          fs.cpSync(source, path.join(temp, 'asset'), { recursive: true });
          fs.rmSync(dest, { recursive: true, force: true });
          fs.renameSync(path.join(temp, 'asset'), dest);
        } finally { fs.rmSync(temp, { recursive: true, force: true }); }
      }
    }
    atomic(manifestFile, JSON.stringify(manifest, null, 2) + '\n');
  }
  return { version: value, dryRun: !!opts['dry-run'], artifacts: entries.map(e => e.destination), manifest: path.relative(c.root, manifestFile) };
}
module.exports = { build, stage };
