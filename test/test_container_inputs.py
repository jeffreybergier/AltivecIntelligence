#!/usr/bin/env python3
"""Check the actual pre-SDK COPY boundary without compilers or SDK archives."""
from pathlib import Path
import fnmatch
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def generated_directories(directory, names):
    return [name for name in names if (Path(directory) / name).is_dir()
            and any(fnmatch.fnmatch(name, pattern) for pattern in
                    ('build', 'build-*', 'Intermediates', 'tarballs', '__pycache__'))]


class ContainerInputs(unittest.TestCase):
    def test_samples_can_load_from_builder_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage = Path(temporary)
            for line in (ROOT / 'Containerfile').read_text().splitlines():
                if line.startswith('RUN --mount=type=bind,from=altivec_sdk,'):
                    break
                if not line.startswith('COPY '):
                    continue
                args = [arg for arg in shlex.split(line)[1:]
                        if not arg.startswith('--')]
                destination = args[-1]
                if not destination.startswith('/altivec/'):
                    continue
                target = stage / destination.lstrip('/')
                for source in args[:-1]:
                    path = ROOT / source
                    if path.is_dir():
                        shutil.copytree(path, target, dirs_exist_ok=True,
                                        ignore=generated_directories)
                    else:
                        output = target / path.name if destination.endswith('/') else target
                        output.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(path, output)
            else:
                self.fail('SDK-dependent build instruction not found')

            runtime = stage / 'altivec'
            self.assertTrue((runtime / 'LICENSE').is_file(),
                            'Library packaging requires LICENSE before the SDK build')
            for app in ('SingleWindow', 'SingleScreen', 'CURLmac', 'CURLphone'):
                with self.subTest(app=app):
                    result = subprocess.run(
                        ['make', '--no-print-directory', '-C', str(runtime / 'apps' / app),
                         'print-config', f'ALTIVEC_ROOT={runtime}'],
                        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                    self.assertEqual(result.returncode, 0, result.stdout)
                    self.assertIn('packages=', result.stdout)


if __name__ == '__main__':
    unittest.main()
