#!/usr/bin/env python3
"""Offline archive discovery/installation tests using tiny synthetic SDKs.

Run: python3 -m unittest discover -s test -p 'test_sdk_discovery.py' -v
Installation tests require Linux's flock; Compose tests require the Docker CLI.
Opt in to the small BuildKit test (uses existing altivec-intelligence:local):
  ALTIVEC_SDK_DOCKER_TESTS=1 python3 -m unittest discover -s test -p 'test_sdk_discovery.py' -v
"""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / 'bin/altivec-sdk'


class SDKDiscovery(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sdk discovery ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.project = self.root / 'project'
        self.home = self.root / 'home'
        self.project.mkdir()
        self.home.mkdir()
        self.local = self.project / '.altivec-sdk'
        self.shared = self.home / '.altivec-sdk'
        self.shared.mkdir()
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith('ALTIVEC_SDK_')}
        self.env.update(HOME=str(self.home),
                        ALTIVEC_SDK_CATALOG=str(self.root / 'catalog.json'),
                        ALTIVEC_SDK_LEGACY_DIR=str(self.root / 'legacy'),
                        ALTIVEC_SDK_MODERN_DIR=str(self.root / 'modern'))
        self.catalog = json.loads((ROOT / 'share/altivec-sdk/catalog.json').read_text())
        for entry in self.catalog['build_sdks']:
            path = self.shared / entry['archive']
            with tarfile.open(path, 'w:xz' if entry['format'] == 'tar.xz' else 'w:gz') as archive:
                member = tarfile.TarInfo(entry['directory'] + '/SDKSettings.plist')
                member.size = 7
                archive.addfile(member, io.BytesIO(b'fixture'))
            entry['archive_bytes'] = path.stat().st_size
            entry['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
            entry['required_paths'] = ['SDKSettings.plist']
        self.save_catalog()
        self.names = [entry['archive'] for entry in self.catalog['build_sdks']]

    def save_catalog(self):
        (self.root / 'catalog.json').write_text(json.dumps(self.catalog))

    def run_sdk(self, *args, good=True, **env):
        result = subprocess.run([str(SDK), *args], cwd=self.project,
                                env={**self.env, **env}, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode == 0, good, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def test_shared_with_missing_and_empty_project_folder(self):
        for create in (False, True):
            if create:
                self.local.mkdir()
            with self.subTest(project_exists=create):
                output = self.run_sdk('preflight')
                for name in self.names:
                    self.assertIn(str(self.shared / name), output)
                    self.assertEqual(self.run_sdk('locate', name).strip(),
                                     str(self.shared / name))
                self.assertEqual(self.run_sdk('status').count('available'), 3)

    def test_home_precedence_and_split_archives(self):
        self.local.mkdir()
        shutil.copy2(self.shared / self.names[0], self.local)
        (self.local / self.names[0]).write_text('invalid lower-priority archive')
        shutil.move(str(self.shared / self.names[1]), self.local)
        for command in ('preflight', 'status'):
            output = self.run_sdk(command)
            self.assertIn(str(self.shared / self.names[0]), output)
            self.assertIn(str(self.local / self.names[1]), output)
            self.assertIn(str(self.shared / self.names[2]), output)

    def test_invalid_home_entries_do_not_fall_back(self):
        self.local.mkdir()
        shutil.copy2(self.shared / self.names[0], self.local)
        (self.shared / self.names[0]).unlink()
        target = self.shared / self.names[0]
        for kind in ('corrupt', 'directory', 'symlink', 'broken-symlink'):
            with self.subTest(kind=kind):
                if kind == 'corrupt':
                    target.write_bytes(b'x' * (self.local / self.names[0]).stat().st_size)
                elif kind == 'directory':
                    target.mkdir()
                else:
                    target.symlink_to(self.local / self.names[0] if kind == 'symlink'
                                      else self.root / 'absent')
                self.assertIn(str(target), self.run_sdk('preflight', good=False))
                self.assertIn(str(target), self.run_sdk('locate', self.names[0], good=False))
                self.assertIn('invalid', self.run_sdk('status'))
                if shutil.which('flock'):
                    self.run_sdk('install', good=False)
                    self.assertFalse((self.root / 'legacy').exists())
                    self.assertFalse((self.root / 'modern').exists())
                if kind == 'directory':
                    target.rmdir()
                else:
                    target.unlink()

    def test_custom_path_is_last_fallback(self):
        custom = self.root / 'custom'
        custom.mkdir()
        self.local.mkdir()
        for variable in ('ALTIVEC_SDK_ARCHIVE_DIR', 'ALTIVEC_SDK_HOST_DIR'):
            # Setting an empty custom folder does not hide home archives.
            self.run_sdk('preflight', **{variable: str(custom)})
        shutil.move(str(self.shared / self.names[1]), self.local)
        shutil.move(str(self.shared / self.names[2]), custom)
        output = self.run_sdk('preflight', ALTIVEC_SDK_ARCHIVE_DIR=str(custom))
        for directory, name in zip((self.shared, self.local, custom), self.names):
            self.assertIn(str(directory / name), output)
        shutil.copy2(custom / self.names[2], self.local)
        (custom / self.names[2]).write_text('invalid lower-priority archive')
        self.run_sdk('preflight', ALTIVEC_SDK_ARCHIVE_DIR=str(custom))
        # An invalid project copy must not silently use the custom fallback.
        shutil.copy2(self.local / self.names[2], custom / self.names[2])
        (self.local / self.names[2]).write_text('invalid project archive')
        self.run_sdk('preflight', good=False, ALTIVEC_SDK_ARCHIVE_DIR=str(custom))
        (self.local / self.names[2]).unlink()
        self.run_sdk('preflight', ALTIVEC_SDK_HOST_DIR=str(custom))
        self.run_sdk('preflight', good=False,
                     ALTIVEC_SDK_ARCHIVE_DIR=str(self.root / 'missing'),
                     ALTIVEC_SDK_HOST_DIR=str(custom))

    def test_build_only_source_locations(self):
        self.local.mkdir()
        shutil.move(str(self.shared / self.names[0]), self.local)
        output = self.run_sdk('preflight', ALTIVEC_SDK_PROJECT_DIR=str(self.local),
                              ALTIVEC_SDK_SHARED_DIR=str(self.shared))
        self.assertIn(str(self.local / self.names[0]), output)
        self.assertIn(str(self.shared / self.names[1]), output)

    def test_missing_everywhere_and_unknown_archive(self):
        shutil.rmtree(self.shared)
        output = self.run_sdk('preflight', good=False)
        self.assertIn(str(self.local), output)
        self.assertIn(str(self.shared), output)
        self.assertEqual(self.run_sdk('status').count('missing'), 6)
        self.run_sdk('locate', '../anything', good=False)
        self.run_sdk('locate', good=False)

    def test_checksum_valid_but_unsafe_archive_is_invalid(self):
        self.local.mkdir()
        entry = self.catalog['build_sdks'][0]
        path = self.shared / entry['archive']
        with tarfile.open(path, 'w:xz') as archive:
            member = tarfile.TarInfo('../escape')
            member.size = 1
            archive.addfile(member, io.BytesIO(b'x'))
        entry['archive_bytes'] = path.stat().st_size
        entry['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.save_catalog()
        self.assertIn('unsafe path', self.run_sdk('preflight', good=False))
        self.assertIn('invalid', self.run_sdk('status'))

    @unittest.skipUnless(os.environ.get('ALTIVEC_SDK_DOCKER_TESTS') == '1',
                         'opt-in BuildKit smoke test requires an existing local image')
    def test_buildkit_archive_mounts(self):
        # Use the production SDK mount declarations, but tiny fixtures instead
        # of rebuilding all toolchains. Nothing is downloaded by the RUN step.
        self.local.mkdir()
        shutil.move(str(self.shared / self.names[0]), self.local)
        context = self.root / 'build-context'
        context.mkdir()
        shutil.copy2(SDK, context / 'altivec-sdk')
        shutil.copy2(self.root / 'catalog.json', context)
        mounts = [line.strip().removeprefix('RUN ').removesuffix(chr(92)).strip()
                  for line in (ROOT / 'Containerfile').read_text().splitlines()
                  if '--mount=type=bind,from=altivec_sdk' in line]
        self.assertEqual(len(mounts), 2)
        image = os.environ.get('ALTIVEC_SDK_TEST_IMAGE', 'altivec-intelligence:local')
        dockerfile = '\n'.join([
            f'FROM {image}',
            'COPY altivec-sdk /usr/local/bin/altivec-sdk',
            'COPY catalog.json /test-catalog.json',
            'ENV ALTIVEC_SDK_CATALOG=/test-catalog.json',
            'ENV ALTIVEC_SDK_PROJECT_DIR=/altivec-sdk',
            'ENV ALTIVEC_SDK_SHARED_DIR=/altivec-sdk-shared',
            'ENV ALTIVEC_SDK_LEGACY_DIR=/test-installed/legacy',
            'ENV ALTIVEC_SDK_MODERN_DIR=/test-installed/modern',
            'ARG ALTIVEC_SDK_ARCHIVE_DIR=""',
            'RUN ' + ' '.join(mounts) + ' altivec-sdk preflight && '
            'altivec-sdk install && altivec-sdk uninstall && '
            'test -f /altivec-sdk/MacOSX10.5.sdk.tar.xz && '
            'test -f /altivec-sdk-shared/MacOSX11.3.sdk.tar.xz',
            'RUN test ! -e /altivec-sdk/MacOSX10.5.sdk.tar.xz && '
            'test ! -e /altivec-sdk-shared/MacOSX11.3.sdk.tar.xz && '
            'test ! -e /test-installed/legacy/MacOSX10.5.sdk',
        ]) + '\n'
        (context / 'Dockerfile').write_text(dockerfile)
        builder = subprocess.check_output(['docker', 'context', 'show'], text=True).strip()
        result = subprocess.run([
            'docker', 'buildx', 'build', '--builder', builder,
            '--network=none', '--pull=false', '--progress=plain',
            '--output=type=cacheonly',
            '--build-context', f'altivec_sdk={self.local}',
            '--build-context', f'altivec_sdk_shared={self.shared}', str(context),
        ], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which('flock'), 'install requires Linux flock')
    def test_install_split_set_and_uninstall_preserve_sources(self):
        self.local.mkdir()
        shutil.move(str(self.shared / self.names[0]), self.local)
        output = self.run_sdk('install')
        for entry in self.catalog['build_sdks']:
            source = (self.local if entry['archive'] == self.names[0] else self.shared) / entry['archive']
            self.assertIn(f'from {source}', output)
            destination = self.root / entry['destination'] / entry['directory']
            self.assertEqual((destination / 'SDKSettings.plist').read_bytes(), b'fixture')
        self.assertEqual(self.run_sdk('status').count('installed'), 3)
        self.assertEqual(self.run_sdk('install').count('already installed'), 3)
        self.run_sdk('uninstall')
        self.assertTrue((self.local / self.names[0]).is_file())
        self.assertTrue((self.shared / self.names[1]).is_file())
        self.assertFalse((self.root / 'legacy' / 'MacOSX10.5.sdk').exists())


@unittest.skipUnless(shutil.which('docker'), 'Compose configuration requires Docker CLI')
class ComposeDiscovery(unittest.TestCase):
    def test_runtime_and_build_source_mappings(self):
        with tempfile.TemporaryDirectory(prefix='sdk compose ') as temporary:
            home = Path(temporary) / 'home'
            env = {k: v for k, v in os.environ.items()
                   if not k.startswith(('ALTIVEC_', 'COMPOSE_'))}
            env['DOCKER_CONFIG'] = os.environ.get('DOCKER_CONFIG', str(Path.home() / '.docker'))
            env['HOME'] = str(home)
            for filename in ('compose.yml', 'templates/compose.yml'):
                with self.subTest(filename=filename):
                    result = subprocess.run(
                        ['docker', 'compose', '--env-file', '/dev/null',
                         '--profile', 'tools', '-f', str(ROOT / filename),
                         'config', '--format', 'json'],
                        env=env, text=True, capture_output=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    model = json.loads(result.stdout)
                    for service in model['services'].values():
                        mounts = {m['target']: m for m in service['volumes']}
                        self.assertNotIn('/altivec-sdk', mounts)
                        self.assertNotIn('/altivec-sdk-shared', mounts)
                        self.assertEqual(mounts['/root']['source'], str(home / '.altivec'))
                        self.assertEqual(mounts[service['working_dir']]['source'],
                                         str((ROOT / filename).parent))
                        self.assertFalse(any(key.startswith('ALTIVEC_SDK_')
                                             for key in service.get('environment', {})))
                        if 'build' in service:
                            contexts = service['build']['additional_contexts']
                            self.assertEqual(contexts['altivec_sdk'], str(ROOT / '.altivec-sdk'))
                            self.assertEqual(contexts['altivec_sdk_shared'],
                                             str(home / '.altivec/.altivec-sdk'))


if __name__ == '__main__':
    unittest.main()
