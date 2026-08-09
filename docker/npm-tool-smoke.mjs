#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
const failures = [];

function commandOutput(command, args = []) {
  const output = execFileSync(command, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: 30_000,
  }).trim();
  if (!output) throw new Error('command produced no output');
  return output.split('\n')[0];
}

async function check(label, action) {
  try {
    const detail = await action();
    console.log(`PASS ${label}${detail ? `: ${detail}` : ''}`);
  } catch (error) {
    const stderr = error?.stderr?.toString().trim();
    const message = stderr || error?.message || String(error);
    console.error(`FAIL ${label}: ${message.split('\n')[0]}`);
    failures.push(label);
  }
}

function packageRoot(packageName, searchRoot) {
  const resolver = createRequire(join(searchRoot, 'package.json'));
  let current = dirname(resolver.resolve(packageName));
  while (current !== dirname(current)) {
    const manifestPath = join(current, 'package.json');
    if (existsSync(manifestPath)) {
      const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
      if (manifest.name === packageName) return current;
    }
    current = dirname(current);
  }
  throw new Error(`could not locate package root for ${packageName}`);
}

function globalPackageRoot(packageName, globalRoot) {
  const root = join(globalRoot, ...packageName.split('/'));
  const manifest = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
  if (manifest.name !== packageName) {
    throw new Error(`unexpected package at ${root}: ${manifest.name}`);
  }
  return root;
}

function packageBinary(packageDir, binaryName) {
  const manifest = require(join(packageDir, 'package.json'));
  const relative =
    typeof manifest.bin === 'string' ? manifest.bin : manifest.bin?.[binaryName];
  if (!relative) throw new Error(`${manifest.name} does not expose ${binaryName}`);
  return join(packageDir, relative);
}

function requireFrom(packageDir, packageName) {
  return createRequire(join(packageDir, 'package.json'))(packageName);
}

async function smokePty(nodePty) {
  await new Promise((resolve, reject) => {
    const expected = 'altivec-node-pty-smoke';
    let output = '';
    const child = nodePty.spawn('/bin/sh', ['-lc', `printf ${expected}`], {
      cols: 80,
      cwd: '/tmp',
      env: process.env,
      name: 'xterm',
      rows: 24,
    });
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error('PTY smoke command timed out'));
    }, 10_000);
    child.onData((data) => {
      output += data;
    });
    child.onExit(({ exitCode }) => {
      clearTimeout(timer);
      if (exitCode !== 0) {
        reject(new Error(`PTY smoke command exited with ${exitCode}`));
      } else if (!output.includes(expected)) {
        reject(new Error('PTY smoke output was missing its marker'));
      } else {
        resolve();
      }
    });
  });
}

const globalRoot = commandOutput('npm', ['root', '-g']);
const kimiRoot = globalPackageRoot('@moonshot-ai/kimi-code', globalRoot);
const piRoot = globalPackageRoot('@earendil-works/pi-coding-agent', globalRoot);
const webcrackRoot = globalPackageRoot('webcrack', globalRoot);
const wranglerRoot = globalPackageRoot('wrangler', globalRoot);

await check('Claude CLI', () => commandOutput('claude', ['--version']));
await check('OpenCode CLI', () => commandOutput('opencode', ['--version']));
await check('Kimi CLI', () => commandOutput('kimi', ['--version']));
await check('Wrangler CLI', () => commandOutput('wrangler', ['--version']));
await check('Pi CLI', () => commandOutput('pi', ['--version']));
await check('webcrack CLI', () => commandOutput('webcrack', ['--version']));

await check('node-pty spawn', async () => {
  await smokePty(requireFrom(kimiRoot, 'node-pty'));
});

await check('isolated-vm load', () => {
  const isolatedVm = requireFrom(webcrackRoot, 'isolated-vm');
  const isolate = new isolatedVm.Isolate({ memoryLimit: 8 });
  isolate.dispose();
});

await check('esbuild binary', () => {
  const root = packageRoot('esbuild', wranglerRoot);
  return commandOutput(packageBinary(root, 'esbuild'), ['--version']);
});

await check('workerd binary', () => {
  const root = packageRoot('workerd', wranglerRoot);
  return commandOutput(packageBinary(root, 'workerd'), ['--version']);
});

await check('@google/genai load', async () => {
  const resolver = createRequire(join(piRoot, 'package.json'));
  await import(pathToFileURL(resolver.resolve('@google/genai')));
});

await check('protobufjs load', () => {
  requireFrom(piRoot, 'protobufjs');
});

if (failures.length > 0) {
  console.error(`npm tool smoke failed: ${failures.join(', ')}`);
  process.exit(1);
}

console.log('npm tool smoke passed');
