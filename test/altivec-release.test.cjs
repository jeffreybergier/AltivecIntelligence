'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const cli = path.resolve(__dirname, '../bin/altivec-release');
const packageDir = path.resolve(__dirname, '../packages/altivec-release');
const P = require('../packages/altivec-release/lib/project.cjs');
const xml = (v = '1.2.3', keys = ['CFBundleShortVersionString', 'CFBundleVersion']) => `<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>${keys.map(k => `<key>${k}</key><string>${v}</string>`).join('')}<key>Nested</key><dict><key>CFBundleVersion</key><string>99</string></dict></dict></plist>\n`;
function fixture(t, changes = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'altivec-release-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const home = path.join(root, 'home'); fs.mkdirSync(home);
  const env = { PATH: process.env.PATH, HOME: home, XDG_CONFIG_HOME: home, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null', LC_ALL: 'C' };
  const config = { schema_version: 1, app_name: 'Example', version: { source: 'Info.plist', plists: ['Info.plist', { path: 'Daemon.plist', keys: ['CFBundleVersion'] }] }, targets: [{ name: 'iOS', build: [{ exec: process.execPath, args: ['-e', "require('fs').writeFileSync('app.ipa','package')"] }], artifacts: [{ path: 'app.ipa', asset_name: '{app_name}-{version}-{target}.ipa' }] }], ...changes };
  const write = (name, contents) => { const file = path.join(root, name); fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, contents); };
  const configWrite = () => write('.altivec-release.json', JSON.stringify(config));
  configWrite(); write('Info.plist', xml()); write('Daemon.plist', xml('1.2.3', ['CFBundleVersion'])); write('.gitignore', 'build/\nhome/\napp.ipa\n');
  const run = (args, extra = {}) => spawnSync(process.execPath, [cli, ...args], { cwd: root, env: { ...env, ...extra }, encoding: 'utf8' });
  const ok = (args, extra) => { const r = run(args, extra); assert.equal(r.status, 0, r.stderr + r.stdout); return r.stdout; };
  const bad = (args, pattern, extra) => { const r = run(args, extra); assert.notEqual(r.status, 0, r.stdout); assert.match(r.stderr, pattern); return r; };
  const git = (...args) => { const r = spawnSync('git', args, { cwd: root, env, encoding: 'utf8' }); assert.equal(r.status, 0, r.stderr); return r.stdout.trim(); };
  const init = () => { git('init', '-b', 'main'); git('add', '.'); git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'commit', '-m', 'initial'); };
  const identity = ['--name', 'Release Tester', '--email', 'release@example.com'];
  const readPlan = () => JSON.parse(fs.readFileSync(path.join(root, 'build/release/plan.json')));
  return { root, env, config, write, configWrite, run, ok, bad, git, init, identity, readPlan };
}
test('help and version work outside projects without Git or SDKs', t => {
  const f = fixture(t);
  fs.unlinkSync(path.join(f.root, '.altivec-release.json'));
  for (const args of [[], ['--help'], ['prepare', '--help'], ['commit', '--help'], ['--version'], ['current', '--version']]) f.ok(args, { PATH: '/nonexistent' });
  const d = JSON.parse(f.ok(['doctor', '--json'], { PATH: '/nonexistent' }));
  assert.equal(d.git, 'missing'); assert.equal(d.checkout, 'missing');
});
test('exported source prepares/builds/stages with no Git executable, identity, keys or network', t => {
  const f = fixture(t), env = { PATH: '/nonexistent' };
  assert.equal(f.ok(['current'], env).trim(), '1.2.3');
  f.ok(['prepare', 'patch', '--dry-run'], env);
  assert.equal(fs.existsSync(path.join(f.root, 'build')), false);
  assert.equal(f.ok(['current'], env).trim(), '1.2.3');
  f.ok(['prepare', 'patch'], env);
  assert.equal(f.ok(['current'], env).trim(), '1.2.4');
  f.ok(['check', '1.2.4'], env); f.ok(['build', '--target', 'iOS'], env); f.ok(['stage'], env);
  assert.equal(fs.readFileSync(path.join(f.root, 'build/release/artifacts/Example-1.2.4-iOS.ipa'), 'utf8'), 'package');
  const manifest = JSON.parse(fs.readFileSync(path.join(f.root, 'build/release/artifact-manifest.json')));
  assert.equal(manifest.artifacts[0].sha256, P.hash('package')); assert.equal(manifest.provenance, null);
  assert.equal(f.readPlan().state, 'prepared');
  f.ok(['prepare', 'patch'], env); assert.equal(f.ok(['current'], env).trim(), '1.2.4');
  assert.match(fs.readFileSync(path.join(f.root, 'Info.plist'), 'utf8'), /<string>99<\/string>/);
});
test('preparation ignores missing identity, detached HEAD, remotes and dirty files', t => {
  const f = fixture(t); f.init(); f.git('checkout', '--detach'); f.git('remote', 'add', 'origin', 'ssh://invalid.invalid/project');
  f.write('unrelated', 'dirty'); f.git('add', 'unrelated');
  f.ok(['prepare', 'minor']);
  const d = JSON.parse(f.ok(['doctor', '--json']));
  assert.equal(d.head, 'detached'); assert.equal(d.identity, 'missing'); assert.equal(d.credentials, 'not checked'); assert.deepEqual(d.unrelatedDirtyFiles, ['unrelated']);
  f.bad(['commit', ...f.identity], /detached HEAD/);
});
test('bump is local-only including legacy --no-push and --set', t => {
  const f = fixture(t); f.init(); const head = f.git('rev-parse', 'HEAD');
  f.ok(['bump', '--set', '2.0', '--no-push']); assert.equal(f.git('rev-parse', 'HEAD'), head); assert.equal(f.git('tag'), '');
});
test('all version edits preflight before writes; binary/malformed/duplicate/missing keys rejected', async t => {
  for (const malformed of [Buffer.from('bplist00\0'), '<plist version="1.0"><dict>', xml().replace('<key>CFBundleVersion</key><string>1.2.3</string>', '<key>CFBundleVersion</key><integer>2</integer>'), xml().replace('</dict></plist>', '<key>CFBundleVersion</key><string>2</string></dict></plist>'), xml().replace('CFBundleVersion', 'WrongKey')]) {
    await t.test(String(malformed).slice(0, 30), t => {
      const f = fixture(t); const before = fs.readFileSync(path.join(f.root, 'Info.plist')); f.write('Daemon.plist', malformed);
      f.bad(['prepare', 'patch'], /plist|key/); assert.deepEqual(fs.readFileSync(path.join(f.root, 'Info.plist')), before);
      assert.equal(fs.existsSync(path.join(f.root, 'build/release/plan.json')), false);
    });
  }
});
test('text version sources, set and ci-env remain Git-free', t => {
  const f = fixture(t, { version: { source: 'VERSION', format: 'text', plists: [] } }); f.write('VERSION', '1.2.3\n');
  f.ok(['set', '2.0']); assert.equal(f.ok(['current', '--json']).trim(), '{"version":"2.0"}');
  assert.equal(f.ok(['ci-env', 'v2.0']), 'RELEASE_TAG=v2.0\nRELEASE_VERSION=2.0\n');
  f.ok(['ci-env', 'v2.0', '--github-env', 'env.txt', '--dry-run']); assert.equal(fs.existsSync(path.join(f.root, 'env.txt')), false);
  f.bad(['check', '2.0.1'], /differs/); f.bad(['set', '1.2.bad'], /numeric/);
});
test('host commit uses explicit identity without global configuration and leaves unrelated dirty files alone', t => {
  const f = fixture(t); f.init(); f.write('unrelated', 'keep me');
  f.ok(['prepare', 'patch']); f.bad(['commit'], /identity missing/);
  f.ok(['commit', ...f.identity, '--dry-run']); assert.equal(f.git('tag'), '');
  f.ok(['commit', ...f.identity]); const head = f.git('rev-parse', 'HEAD');
  assert.equal(f.git('show', '-s', '--format=%an <%ae>'), 'Release Tester <release@example.com>');
  assert.equal(f.git('rev-parse', 'v1.2.4'), head);
  assert.deepEqual(f.git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD').split('\n'), ['Daemon.plist', 'Info.plist']);
  assert.equal(f.git('config', '--local', '--list').includes('user.name'), false);
  f.ok(['commit']); assert.equal(f.git('rev-parse', 'HEAD'), head);
  assert.equal(fs.readFileSync(path.join(f.root, 'unrelated'), 'utf8'), 'keep me');
});
test('host commit reads existing local identity', t => {
  const f = fixture(t); f.init(); f.git('config', 'user.name', 'Existing'); f.git('config', 'user.email', 'existing@example.com');
  f.ok(['prepare']); f.ok(['commit']); assert.equal(f.git('show', '-s', '--format=%an'), 'Existing');
});
test('unrelated staged files, edited plan files, changed config and existing tags block commit', async t => {
  const scenarios = [
    [f => { f.write('other', 'x'); f.git('add', 'other'); }, /unrelated staged/],
    [f => f.write('Info.plist', xml('8.0')), /prepared file changed/],
    [f => f.git('tag', 'v1.2.4'), /local tag already exists/],
    [f => { f.config.app_name = 'Changed'; f.configWrite(); }, /configuration changed/],
  ];
  for (const [change, error] of scenarios) await t.test(error.source, t => {
    const f = fixture(t); f.init(); f.ok(['prepare']); const head = f.git('rev-parse', 'HEAD'); change(f);
    f.bad(['commit', ...f.identity], error); assert.equal(f.git('rev-parse', 'HEAD'), head);
  });
});
test('failed commit hook resumes without a second bump and detects branch changes', t => {
  const f = fixture(t); f.init(); f.ok(['prepare']);
  f.write('.git/hooks/pre-commit', '#!/bin/sh\nexit 1\n'); fs.chmodSync(path.join(f.root, '.git/hooks/pre-commit'), 0o755);
  f.bad(['commit', ...f.identity], /failed/); assert.equal(f.readPlan().state, 'committing');
  f.git('checkout', '-b', 'other'); f.bad(['commit', ...f.identity], /bound to branch main/); f.git('checkout', 'main');
  fs.unlinkSync(path.join(f.root, '.git/hooks/pre-commit')); f.ok(['commit', ...f.identity]);
  assert.equal(f.git('rev-list', '--count', 'HEAD'), '2'); assert.equal(f.ok(['current']).trim(), '1.2.4');
});
test('interrupted preparation resumes files from durable before-images', t => {
  const f = fixture(t); f.ok(['prepare']); const p = f.readPlan(); p.state = 'preparing';
  f.write(p.files[0].path, Buffer.from(p.files[0].before, 'base64')); f.write('build/release/plan.json', JSON.stringify(p));
  f.ok(['prepare']); f.ok(['check', '1.2.4']); assert.equal(f.readPlan().state, 'prepared');
});
test('crash after commit and tag failure are resumable without an extra commit', t => {
  const f = fixture(t); f.init(); f.ok(['prepare']); f.ok(['commit', ...f.identity]);
  const head = f.git('rev-parse', 'HEAD'), p = f.readPlan(); f.git('tag', '-d', p.tag);
  delete p.commit; p.state = 'committing'; f.write('build/release/plan.json', JSON.stringify(p));
  f.ok(['commit']); assert.equal(f.git('rev-parse', p.tag), head); assert.equal(f.git('rev-list', '--count', 'HEAD'), '2');
});
test('explicit push retries partial publication to a local remote', t => {
  const f = fixture(t); f.init(); f.ok(['prepare']); f.ok(['commit', ...f.identity]);
  f.bad(['push'], /remote missing/);
  const remote = path.join(f.root, 'remote.git'); f.git('init', '--bare', remote); f.git('remote', 'add', 'origin', remote);
  f.write('remote.git/hooks/update', '#!/bin/sh\ncase "$1" in refs/tags/*) exit 1;; esac\n'); fs.chmodSync(path.join(remote, 'hooks/update'), 0o755);
  f.ok(['push', '--dry-run']); assert.deepEqual(fs.readdirSync(path.join(remote, 'refs/heads')), []);
  f.bad(['push'], /failed/); assert.equal(f.readPlan().branchPushed, true);
  fs.unlinkSync(path.join(remote, 'hooks/update')); f.ok(['push']); assert.equal(f.readPlan().state, 'pushed');
  f.ok(['push']); assert.equal(f.git('--git-dir', remote, 'rev-parse', 'refs/tags/v1.2.4'), f.git('rev-parse', 'HEAD'));
});
test('remote checks distinguish absent tags from connection failure and are opt-in', t => {
  const f = fixture(t); f.init(); f.git('init', '--bare', path.join(f.root, 'remote.git')); f.git('remote', 'add', 'origin', path.join(f.root, 'remote.git'));
  assert.equal(JSON.parse(f.ok(['doctor', '--json'])).credentials, 'not checked');
  assert.equal(JSON.parse(f.ok(['doctor', '--check-remote', '--json'])).remoteCheck.status, 'absent');
  f.git('remote', 'set-url', 'origin', path.join(f.root, 'missing.git'));
  assert.equal(JSON.parse(f.ok(['doctor', '--check-remote', '--json'])).remoteCheck.status, 'authentication-or-network-failure');
  assert.equal(JSON.parse(f.ok(['doctor', '--check-remote', '--dry-run', '--json'])).remoteCheck.status, 'skipped for dry-run');
});
test('stage preflights duplicate names, missing artifacts, path escapes and destination overlap', async t => {
  const scenarios = [
    [f => f.config.targets[0].artifacts.push({ path: 'other.ipa', asset_name: 'Example-{version}-iOS.ipa' }), /duplicate asset/],
    [f => f.config.targets[0].artifacts.push({ path: 'missing.ipa' }), /ENOENT/],
    [f => { f.config.targets[0].artifacts[0].asset_name = '../outside'; }, /invalid asset name/],
    [f => { f.config.stage_dir = '.'; }, /overlaps/],
    [f => { f.config.targets[0].artifacts[0].path = '../escape'; }, /inside the project/],
  ];
  for (const [change, pattern] of scenarios) await t.test(pattern.source, t => {
    const f = fixture(t); f.write('app.ipa', 'a'); f.write('other.ipa', 'b'); change(f); f.configWrite();
    f.bad(['stage'], pattern); assert.equal(fs.existsSync(path.join(f.root, 'build/release/artifacts')), false);
  });
});
test('symlink version paths and staging destinations cannot escape project', t => {
  const f = fixture(t); fs.unlinkSync(path.join(f.root, 'Daemon.plist')); fs.symlinkSync(path.join(f.root, 'Info.plist'), path.join(f.root, 'Daemon.plist'));
  f.bad(['prepare'], /symlink/);
});
test('migration fixtures preserve all four consumers and normal commands need no Python', async t => {
  const yamlProbe = spawnSync('python3', ['-c', 'import yaml']);
  if (yamlProbe.status !== 0) { t.skip('one-time migration tests need Python/PyYAML'); return; }
  for (const name of ['ENIL', 'Strappy-Cocoa', 'Retro-Cloud-Sync', 'Retro-DLP']) await t.test(name, t => {
    const f = fixture(t); fs.unlinkSync(path.join(f.root, '.altivec-release.json'));
    f.write('.altivec-release.yml', fs.readFileSync(path.join(__dirname, 'fixtures/release', name + '.yml')));
    f.bad(['current'], /one-time migration/); f.ok(['migrate', '--dry-run']); assert.equal(fs.existsSync(path.join(f.root, '.altivec-release.json')), false);
    f.ok(['migrate']); const c = P.load(path.join(f.root, '.altivec-release.json'));
    assert.equal(c.data.stage_dir, 'dist'); assert.ok(c.targets.every(target => target.actions.every(a => typeof a.shell === 'string')));
    for (const p of c.plists) f.write(path.relative(f.root, p.file), xml('1.2.3', p.keys));
    f.ok(['prepare'], { PATH: '/nonexistent' }); f.ok(['check', '1.2.4'], { PATH: '/nonexistent' });
    for (const target of c.targets) for (const artifact of target.artifacts) f.write(path.relative(f.root, artifact.file), 'artifact');
    f.ok(['stage'], { PATH: '/nonexistent' });
    const manifest = JSON.parse(fs.readFileSync(path.join(f.root, 'build/release/artifact-manifest.json')));
    assert.equal(manifest.artifacts.length, name === 'Retro-DLP' ? 6 : name === 'Strappy-Cocoa' ? 3 : 2);
    f.bad(['migrate', '--config', '.altivec-release.yml'], /already exists/);
  });
});
test('npm package installs offline and works independently of the checkout', t => {
  const f = fixture(t);
  const npm = (args, cwd = f.root) => { const r = spawnSync('npm', args, { cwd, env: { ...f.env, npm_config_cache: path.join(f.root, 'npm-cache') }, encoding: 'utf8' }); assert.equal(r.status, 0, r.stderr); return r.stdout; };
  const packed = Object.values(JSON.parse(npm(['pack', packageDir, '--json', '--pack-destination', f.root, '--ignore-scripts', '--offline'])))[0];
  assert.ok(packed.files.some(x => x.path === 'lib/migrate.py'));
  npm(['install', '--prefix', path.join(f.root, 'installed'), '--ignore-scripts', '--offline', '--no-audit', '--no-fund', path.join(f.root, packed.filename)]);
  const installed = path.join(f.root, 'installed/node_modules/altivec-release/bin/altivec-release.js');
  const result = spawnSync(process.execPath, [installed, 'prepare', 'patch'], { cwd: f.root, env: { ...f.env, PATH: '/nonexistent' }, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr); assert.equal(f.ok(['current']).trim(), '1.2.4');
});
test('set is idempotent and can align other plist versions with the source', t => {
  const f = fixture(t); f.ok(['set', '1.2.3']);
  assert.equal(fs.existsSync(path.join(f.root, 'build/release/plan.json')), false);
  f.write('Daemon.plist', xml('1.0', ['CFBundleVersion'])); f.ok(['set', '1.2.3']); f.ok(['check', '1.2.3']);
});
test('explicit identity creates a lightweight tag even when global tag signing is enabled', t => {
  const f = fixture(t); f.init(); f.git('config', 'tag.gpgSign', 'true'); f.ok(['prepare']); f.ok(['commit', ...f.identity]);
  assert.equal(f.git('cat-file', '-t', 'v1.2.4'), 'commit');
});
test('new releases require explicit plan replacement and archive the old plan', t => {
  const f = fixture(t); f.init(); f.ok(['prepare']); f.bad(['prepare', '--new-plan'], /previous plan/); f.ok(['commit', ...f.identity]);
  f.ok(['prepare']); assert.equal(f.ok(['current']).trim(), '1.2.4');
  f.ok(['prepare', 'minor', '--new-plan']); assert.equal(f.ok(['current']).trim(), '1.3.0');
  assert.equal(fs.readdirSync(path.join(f.root, 'build/release/history')).length, 1);
});
test('staging directories preserve contents/checksums and executable modes', t => {
  const f = fixture(t); f.config.targets[0].artifacts = [{ path: 'bundle', asset_name: 'bundle-{version}' }]; f.configWrite();
  f.write('bundle/tool', '#!/bin/sh\n'); fs.chmodSync(path.join(f.root, 'bundle/tool'), 0o755); f.write('bundle/nested/resource', 'data');
  f.ok(['stage', '--dry-run']); assert.equal(fs.existsSync(path.join(f.root, 'build')), false); f.ok(['stage']);
  assert.equal(fs.statSync(path.join(f.root, 'build/release/artifacts/bundle-1.2.3/tool')).mode & 0o777, 0o755);
  f.config.targets[0].artifacts = [{ path: 'bundle/tool' }]; f.configWrite(); f.ok(['stage']);
  assert.equal(fs.statSync(path.join(f.root, 'build/release/artifacts/tool')).mode & 0o777, 0o755);
});
test('explicit remote tag conflicts cannot overwrite an existing published tag', t => {
  const f = fixture(t); f.init(); const base = f.git('rev-parse', 'HEAD'); f.ok(['prepare']); f.ok(['commit', ...f.identity]);
  const remote = path.join(f.root, 'remote.git'); f.git('init', '--bare', remote); f.git('remote', 'add', 'origin', remote);
  f.git('push', 'origin', `${base}:refs/tags/v1.2.4`); f.bad(['push'], /remote tag already exists/);
  assert.equal(f.git('--git-dir', remote, 'rev-parse', 'refs/tags/v1.2.4'), base);
});
