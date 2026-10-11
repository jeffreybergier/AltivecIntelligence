'use strict';
const { spawnSync } = require('node:child_process');
const P = require('./project.cjs');
const { fs, path, hash, fail, read, json, safe, atomic } = P;
const planPath = c => safe(c.root, 'build/release/plan.json');
const save = (c, plan) => atomic(planPath(c), JSON.stringify(plan, null, 2) + '\n');
function withLock(c, action) {
  const lock = safe(c.root, 'build/release/.lock');
  fs.mkdirSync(path.dirname(lock), { recursive: true });
  try { fs.mkdirSync(lock); }
  catch { fail('release operation locked. If no release command is running, remove build/release/.lock and retry the same command.'); }
  try { return action(); } finally { fs.rmdirSync(lock); }
}
function plan(c) {
  if (!fs.existsSync(planPath(c))) fail('no prepared plan; run altivec-release prepare patch in the mounted checkout first');
  const p = json(planPath(c));
  if (p.schema_version !== 1 || p.configHash !== c.configHash || !Array.isArray(p.files) || !p.files.length) fail('release plan/configuration changed; review build/release/plan.json');
  P.version(p.version);
  if (p.tag !== c.prefix + p.version || p.message !== P.format(c.message, c, p.version)) fail('invalid plan tag/message');
  const expected = new Set(c.files.map(file => path.relative(c.root, file)));
  for (const f of p.files) {
    if (!expected.delete(f.path) || hash(Buffer.from(f.before, 'base64')) !== f.beforeHash || hash(Buffer.from(f.after, 'base64')) !== f.afterHash) fail('invalid release plan file or checksum');
    safe(c.root, f.path);
  }
  if (expected.size) fail('release plan file list does not match configuration');
  if (!['preparing', 'prepared', 'committing', 'committed', 'tagged', 'pushed'].includes(p.state)) fail('invalid release plan state');
  return p;
}
function verifyFiles(c, p) {
  for (const f of p.files) if (hash(read(safe(c.root, f.path))) !== f.afterHash) fail(`prepared file changed: ${f.path}; restore the reviewed plan content before retrying`);
  P.check(c, p.version);
}
function prepare(c, opts, positional) {
  const existing = fs.existsSync(planPath(c)) ? plan(c) : null;
  if (existing && !opts['new-plan']) {
    if (opts.set && opts.set !== existing.version) fail('a release plan already exists; finish it before preparing another version');
    if (existing.state === 'preparing') {
      for (const f of existing.files) {
        const actual = hash(read(safe(c.root, f.path)));
        if (actual !== f.beforeHash && actual !== f.afterHash) fail(`interrupted preparation: ${f.path} changed; restore its before/after content from plan.json, then retry prepare`);
      }
      if (!opts['dry-run']) {
        for (const f of existing.files) atomic(safe(c.root, f.path), Buffer.from(f.after, 'base64'));
        existing.state = 'prepared'; save(c, existing);
      }
    } else verifyFiles(c, existing);
    return { version: existing.version, tag: existing.tag, state: existing.state, resumed: true, next: 'Review build/release/plan.json and git diff on the host; run altivec-release commit. Do not bump again.' };
  }
  if (existing && !['tagged', 'pushed'].includes(existing.state)) fail('--new-plan requires the previous plan to be locally committed and tagged');
  const old = P.current(c), value = opts.set || P.bump(old, positional || 'patch');
  if (value === old && !opts.allowSame) fail('new release version must differ from the current version');
  const files = P.edits(c, value); // Validate every file before the first write.
  if (opts.allowSame && files.every(f => f.beforeHash === f.afterHash)) return { version: value, changed: false };
  const p = { schema_version: 1, state: 'preparing', configHash: c.configHash, previousVersion: old, version: value, tag: c.prefix + value, message: P.format(c.message, c, value), files };
  if (!opts['dry-run']) {
    if (existing) atomic(safe(c.root, `build/release/history/${hash(JSON.stringify(existing))}.json`), JSON.stringify(existing, null, 2) + '\n');
    save(c, p); // Durable before-images make interrupted multi-file writes resumable.
    for (const f of files) atomic(safe(c.root, f.path), Buffer.from(f.after, 'base64'));
    p.state = 'prepared'; save(c, p);
  }
  return { version: value, previousVersion: old, tag: p.tag, files: files.map(f => f.path), dryRun: !!opts['dry-run'], next: 'In Docker: altivec-release build && altivec-release stage. On the host: review git diff and build/release/plan.json, then altivec-release commit.' };
}
function git(c, args, optional = false, identity = {}) {
  const result = spawnSync('git', ['--literal-pathspecs', ...args], {
    cwd: c.root, encoding: 'utf8', timeout: 30000,
    env: { ...process.env, GIT_TERMINAL_PROMPT: '0', ...identity },
  });
  if (!optional && (result.error || result.status !== 0)) fail(`git ${args[0]} failed: ${(result.stderr || result.error?.message || '').trim()}\nRetry the same release command after fixing the problem; do not prepare another bump.`);
  return { ok: !result.error && result.status === 0, status: result.status, out: (result.stdout || '').replace(/\n$/, ''), error: (result.stderr || result.error?.message || '').trim() };
}
function checkout(c) {
  const root = git(c, ['rev-parse', '--show-toplevel'], true);
  if (!root.ok) fail('Git checkout unavailable. Prepare/build/stage work without Git; run commit from the authenticated host checkout.');
  if (fs.realpathSync(root.out) !== c.root) fail('commit requires the release config at the Git checkout root');
  const branch = git(c, ['symbolic-ref', '--quiet', '--short', 'HEAD'], true).out;
  if (!branch) fail('detached HEAD; switch to the intended release branch on the host');
  const head = git(c, ['rev-parse', '--verify', 'HEAD']).out;
  return { branch, head };
}
function localTag(c, tag) { return git(c, ['rev-parse', '--verify', `refs/tags/${tag}`], true).out; }
function identity(c, opts) {
  if (!!opts.name !== !!opts.email) fail('provide both --name and --email for per-invocation Git identity');
  const env = opts.name ? { GIT_AUTHOR_NAME: opts.name, GIT_AUTHOR_EMAIL: opts.email, GIT_COMMITTER_NAME: opts.name, GIT_COMMITTER_EMAIL: opts.email } : {};
  for (const kind of ['AUTHOR', 'COMMITTER']) {
    const result = git(c, ['-c', 'user.useConfigOnly=true', 'var', `GIT_${kind}_IDENT`], true, env);
    if (!result.ok) fail('Git author/committer identity missing. Run commit on the host, or supply --name "Your Name" --email "you@example.com". Global Git settings are never changed.');
  }
  return env;
}
function noUnrelatedStaged(c, p) {
  const allowed = new Set(p.files.map(f => f.path));
  // --no-renames reports both sides of staged renames independently.
  const raw = git(c, ['diff', '--cached', '--name-only', '--no-renames', '-z']).out;
  if (raw.split('\0').filter(Boolean).some(file => !allowed.has(file))) fail('unrelated staged changes exist; unstage them before altivec-release commit');
}
function commit(c, opts) {
  const p = plan(c);
  if (p.state === 'preparing') fail('preparation was interrupted; rerun altivec-release prepare to finish it first');
  verifyFiles(c, p);
  const { branch, head } = checkout(c);
  noUnrelatedStaged(c, p);
  git(c, ['check-ref-format', `refs/tags/${p.tag}`]);
  if (p.branch && p.branch !== branch) fail(`release plan is bound to branch ${p.branch}; switch back before retrying`);
  let tag = localTag(c, p.tag);
  if (p.commit) {
    if (head !== p.commit) fail('HEAD differs from the recorded release commit; switch back before retrying');
  } else if (p.state === 'committing' && head !== p.base) {
    // A previous commit may have succeeded just before the process stopped.
    const parents = git(c, ['show', '-s', '--format=%P', 'HEAD']).out;
    const tree = git(c, ['rev-parse', 'HEAD^{tree}']).out;
    const message = git(c, ['show', '-s', '--format=%B', 'HEAD']).out;
    if (parents !== p.base || tree !== p.tree || message.trim() !== p.message.trim()) fail('HEAD changed since commit started; cannot safely resume this release plan');
    p.commit = head;
  }
  if (tag && tag !== p.commit) fail(`local tag already exists: ${p.tag}; it is not this plan's release commit`);
  if (!p.commit) {
    const env = identity(c, opts);
    if (p.base && p.base !== head) fail('branch changed since commit started');
    if (opts['dry-run']) return { version: p.version, tag: p.tag, branch, dryRun: true, files: p.files.map(f => f.path), next: 'altivec-release commit (on host)' };
    p.branch = branch; p.base = head;
    git(c, ['add', '--', ...p.files.map(f => f.path)]);
    noUnrelatedStaged(c, p);
    p.tree = git(c, ['write-tree']).out;
    if (p.tree === git(c, ['rev-parse', 'HEAD^{tree}']).out) fail('no version changes to commit');
    p.state = 'committing'; save(c, p);
    git(c, ['-c', 'user.useConfigOnly=true', 'commit', '-m', p.message], false, env);
    const committed = git(c, ['rev-parse', 'HEAD']).out;
    if (git(c, ['rev-parse', 'HEAD^{tree}']).out !== p.tree || git(c, ['show', '-s', '--format=%P', 'HEAD']).out !== p.base) fail('commit hook changed the release tree; review the commit before creating a tag');
    p.commit = committed;
  }
  if (opts['dry-run']) return { version: p.version, commit: p.commit, tag: p.tag, dryRun: true };
  p.state = 'committed'; save(c, p);
  verifyFiles(c, p);
  tag = localTag(c, p.tag);
  if (tag && tag !== p.commit) fail('tag changed during commit; review before retrying');
  if (!tag) git(c, ['tag', '--no-sign', p.tag, p.commit]);
  p.state = 'tagged'; save(c, p);
  return { version: p.version, commit: p.commit, tag: p.tag, next: 'Local commit/tag ready. Only when publication is wanted: altivec-release push (on host).' };
}
function remoteTag(c, tag) {
  const r = git(c, ['ls-remote', '--exit-code', '--tags', 'origin', `refs/tags/${tag}`], true);
  if (r.status === 2) return { status: 'absent' };
  if (!r.ok) return { status: 'authentication-or-network-failure', error: r.error };
  return { status: 'present', object: r.out.split(/\s/)[0] };
}
function push(c, opts) {
  const p = plan(c), { head, branch } = checkout(c);
  verifyFiles(c, p);
  if (!p.commit || head !== p.commit || branch !== p.branch || localTag(c, p.tag) !== p.commit) fail('release commit/tag/branch does not match the plan; run altivec-release commit first');
  const remote = git(c, ['remote', 'get-url', '--push', 'origin'], true);
  if (!remote.ok) fail('origin remote missing; configure it on the host before publication');
  if (p.remoteHash && p.remoteHash !== hash(remote.out)) fail('origin changed during publication; restore it before retrying');
  if (opts['dry-run']) return { tag: p.tag, commit: p.commit, branch, remote: 'origin', dryRun: true, credentials: 'not checked', next: 'altivec-release push contacts origin and publishes the release commit/tag.' };
  // Query the push URL, which may differ from the fetch URL.
  const result = git(c, ['ls-remote', '--exit-code', '--tags', remote.out, `refs/tags/${p.tag}`], true);
  if (!result.ok && result.status !== 2) fail(`remote authentication/network check failed: ${result.error}; no tag absence was assumed`);
  if (result.ok && result.out.split(/\s/)[0] !== p.commit) fail(`remote tag already exists with different content: ${p.tag}`);
  p.remoteHash = hash(remote.out); save(c, p);
  // Full refspecs, no force. Repeating either push is safe after partial failure.
  git(c, ['push', 'origin', `${p.commit}:refs/heads/${p.branch}`]);
  p.branchPushed = true; save(c, p);
  git(c, ['push', 'origin', `refs/tags/${p.tag}:refs/tags/${p.tag}`]);
  p.state = 'pushed'; save(c, p);
  return { tag: p.tag, commit: p.commit, state: p.state };
}
function doctor(c, opts) {
  const root = c || { root: process.cwd() };
  const available = git(root, ['--version'], true).ok;
  const repo = available && git(root, ['rev-parse', '--show-toplevel'], true).ok;
  const branch = repo ? git(root, ['symbolic-ref', '--short', '--quiet', 'HEAD'], true).out : '';
  const author = repo && git(root, ['-c', 'user.useConfigOnly=true', 'var', 'GIT_AUTHOR_IDENT'], true).ok;
  const committer = repo && git(root, ['-c', 'user.useConfigOnly=true', 'var', 'GIT_COMMITTER_IDENT'], true).ok;
  const remote = repo && git(root, ['remote', 'get-url', 'origin'], true).ok;
  const dirty = repo ? git(root, ['status', '--porcelain', '--untracked-files=normal']).out.split('\n').filter(Boolean) : [];
  const result = { project: !!c, git: available ? 'available' : 'missing', checkout: repo ? 'available' : 'missing', identity: author && committer ? 'configured' : 'missing', head: !repo ? 'unavailable' : branch || 'detached', remote: remote ? 'origin' : 'absent', credentials: 'not checked', dirtyFiles: dirty, preparation: c ? 'available without Git identity or credentials' : 'needs release config' };
  if (c && repo) {
    const allowed = new Set(c.files.map(file => path.relative(c.root, file)));
    const tracked = git(root, ['diff', 'HEAD', '--name-only', '--no-renames', '-z']).out.split('\0').filter(Boolean);
    const untracked = git(root, ['ls-files', '--others', '--exclude-standard', '-z']).out.split('\0').filter(Boolean);
    result.unrelatedDirtyFiles = [...new Set([...tracked, ...untracked])].filter(file => !allowed.has(file) && !file.startsWith('build/release/'));
  }
  if (opts['check-remote']) {
    if (opts['dry-run']) result.remoteCheck = { status: 'skipped for dry-run' };
    else if (!remote) result.remoteCheck = { status: 'absent remote' };
    else if (!c) result.remoteCheck = { status: 'needs release config' };
    else {
      const tag = fs.existsSync(planPath(c)) ? plan(c).tag : c.prefix + P.current(c);
      result.remoteCheck = { tag, ...remoteTag(c, tag) };
      result.credentials = result.remoteCheck.status === 'authentication-or-network-failure' ? 'check failed' : 'remote readable; push permission not checked';
    }
  }
  result.next = !c ? 'Copy templates/altivec-release.json to .altivec-release.json.' : 'Docker: altivec-release prepare patch, then build and stage. Host: review changes, then altivec-release commit; explicitly run push when ready to publish.';
  return result;
}
module.exports = { withLock, prepare, commit, push, doctor, git };
