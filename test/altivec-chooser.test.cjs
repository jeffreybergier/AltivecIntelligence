const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { test } = require('node:test');
const { ensureAgentGuidance } = require('../bin/altivec-chooser');
const chooser = path.resolve(__dirname, '../bin/altivec-chooser');

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'altivec-chooser-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const source = path.join(root, 'default.md');
  const destination = path.join(root, 'AGENTS.md');
  fs.writeFileSync(source, 'Default project guidance\n');
  return { root, source, destination };
}

test('default source copies the app template rather than maintainer guidance', (t) => {
  const { destination } = fixture(t);
  const template = path.resolve(__dirname, '../templates/AGENTS.md');
  const copy = fs.copyFileSync;
  t.mock.method(fs, 'copyFileSync', (source, target, flags) => {
    assert.equal(source, '/altivec/templates/AGENTS.md');
    return copy(template, target, flags);
  });
  ensureAgentGuidance(undefined, destination);
  assert.equal(fs.readFileSync(destination, 'utf8'), fs.readFileSync(template, 'utf8'));
  assert.notEqual(fs.readFileSync(destination, 'utf8'),
    fs.readFileSync(path.resolve(__dirname, '../AGENTS.md'), 'utf8'));
});

test('copies defaults once and preserves project edits', (t) => {
  const { source, destination } = fixture(t);
  ensureAgentGuidance(source, destination);
  assert.equal(fs.readFileSync(destination, 'utf8'), 'Default project guidance\n');
  fs.writeFileSync(destination, 'Project guidance\n');
  fs.unlinkSync(source);
  ensureAgentGuidance(source, destination);
  assert.equal(fs.readFileSync(destination, 'utf8'), 'Project guidance\n');
});

for (const kind of ['symlink', 'dangling symlink', 'directory']) {
  test(`preserves existing ${kind} even without a source`, (t) => {
    const { source, destination } = fixture(t);
    const target = path.join(path.dirname(source), 'project.md');
    if (kind === 'directory') fs.mkdirSync(destination);
    else {
      if (kind === 'symlink') fs.writeFileSync(target, 'Custom guidance');
      fs.symlinkSync(target, destination);
    }
    fs.unlinkSync(source);
    ensureAgentGuidance(source, destination);
    if (kind === 'directory') assert.ok(fs.lstatSync(destination).isDirectory());
    else {
      assert.equal(fs.readlinkSync(destination), target);
      if (kind === 'symlink') assert.equal(fs.readFileSync(target, 'utf8'), 'Custom guidance');
      else assert.equal(fs.existsSync(target), false);
    }
  });
}

test('exclusive copy preserves a destination created after the existence check', (t) => {
  const { source, destination } = fixture(t);
  const copy = fs.copyFileSync;
  t.mock.method(fs, 'copyFileSync', (...args) => {
    fs.writeFileSync(destination, 'Concurrent project guidance');
    return copy(...args);
  });
  ensureAgentGuidance(source, destination);
  assert.equal(fs.readFileSync(destination, 'utf8'), 'Concurrent project guidance');
});

test('missing source reports both paths and leaves the destination absent', (t) => {
  const { source, destination } = fixture(t);
  fs.unlinkSync(source);
  assert.throws(() => ensureAgentGuidance(source, destination), (error) => {
    assert.ok(error.message.includes(source));
    assert.ok(error.message.includes(destination));
    assert.match(error.message, /ENOENT/);
    return true;
  });
  assert.equal(fs.existsSync(destination), false);
});

test('unwritable destination reports an actionable failure', (t) => {
  const { source, destination } = fixture(t);
  // Deterministic even when the container tests run as root.
  t.mock.method(fs, 'copyFileSync', () => {
    throw Object.assign(new Error('Permission denied'), { code: 'EACCES' });
  });
  assert.throws(() => ensureAgentGuidance(source, destination), /EACCES.*directory permissions/);
  assert.equal(fs.existsSync(destination), false);
});

test('Codex launches with inline, daemon-free flags and preserves its exit status', (t) => {
  const { root, destination } = fixture(t);
  fs.writeFileSync(destination, 'Existing project instructions');
  fs.symlinkSync(process.execPath, path.join(root, 'node'));
  fs.writeFileSync(path.join(root, 'npm'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
  fs.writeFileSync(path.join(root, 'codex'), `#!/usr/bin/env node
const fs = require('node:fs');
fs.writeFileSync('launch.json', JSON.stringify({
  args: process.argv.slice(2), guidance: fs.readFileSync('AGENTS.md', 'utf8')
}));
process.exit(23);
`, { mode: 0o755 });
  const result = spawnSync(process.execPath, [chooser], {
    cwd: root, env: { ...process.env, PATH: root, TERM: 'dumb' },
    input: '2\n', encoding: 'utf8', timeout: 10000,
  });
  assert.equal(result.status, 23, result.stderr);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(root, 'launch.json'))), {
    args: ['--yolo', '--no-daemon', '--no-alt-screen'],
    guidance: 'Existing project instructions',
  });
});
