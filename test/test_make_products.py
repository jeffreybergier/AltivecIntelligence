#!/usr/bin/env python3
"""Offline Make dependency/packaging contract tests; no Apple SDK required."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FAKE = r'''#!/usr/bin/env python3
import json, pathlib, re, sys
args=sys.argv[1:]
if any(a.startswith('-S') for a in args): sys.exit(0)
if '-verify_arch' in args:
    sys.exit(0 if args[-1] in json.loads(pathlib.Path(args[0]).read_text()) else 1)
if '-create' in args:
    inputs=args[args.index('-create')+1:args.index('-output')]
    arches=[]
    for p in inputs: arches += json.loads(pathlib.Path(p).read_text())
    pathlib.Path(args[-1]).write_text(json.dumps(sorted(set(arches))))
elif 'rcs' in args:
    arches=[]
    for p in args[2:]: arches += json.loads(pathlib.Path(p).read_text())
    pathlib.Path(args[1]).write_text(json.dumps(sorted(set(arches))))
else:
    out=pathlib.Path(args[args.index('-o')+1])
    arch=args[args.index('-arch')+1]
    out.write_text(json.dumps([arch]))
    if '-c' in args:
        source=pathlib.Path(args[args.index('-c')+1])
        headers=[str(source.parent/h) for h in re.findall(r'#include "([^"]+)"', source.read_text())]
        pathlib.Path(args[args.index('-MF')+1]).write_text(str(out)+': '+str(source)+' '+' '.join(headers)+'\n')
'''


class MakeProducts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.tool = self.root / 'tool'
        self.tool.write_text(FAKE)
        self.tool.chmod(0o755)
        self.args = [f'ALTIVEC_ROOT={ROOT}', f'LIPO={self.tool}', f'LDID={self.tool}', 'SYMBOLS=0']
        for a in ('ppc', 'i386', 'x86_64', 'arm64', 'armv7'):
            self.args += [f'CC_{a}={self.tool}', f'AR_{a}={self.tool}', f'SDK_{a}={self.root}']

    def tearDown(self):
        self.tmp.cleanup()

    def fixture(self, name):
        target = self.root / name
        shutil.copytree(ROOT / 'test/fixtures' / name, target, ignore=shutil.ignore_patterns('build', 'build-*'))
        return target

    def make(self, path, *args, good=True):
        p = subprocess.run(['make', '--no-print-directory', '-C', str(path), *self.args, *args],
                           text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if good:
            self.assertEqual(p.returncode, 0, p.stdout)
        else:
            self.assertNotEqual(p.returncode, 0, p.stdout)
        return p.stdout

    def test_three_product_shapes_parallel_configs_and_child_paths(self):
        for name in ('simple', 'daemon', 'products'):
            root = self.fixture(name)
            self.make(root, '-j4', 'debug', 'release')
            for config in ('debug', 'release'):
                archive = root / f'build/macOS/{config}/Fixture/Fixture.zip'
                self.assertTrue(archive.exists())
                with zipfile.ZipFile(archive) as z:
                    self.assertIn('Fixture.app/Contents/MacOS/Fixture', z.namelist())
                    if name == 'daemon':
                        self.assertIn('Fixture.app/Contents/Library/LaunchServices/helper', z.namelist())
            parent = self.make(root, 'print-config', 'BUILD_ROOT=relative')
            child = self.make(root / 'source', 'print-config', 'BUILD_ROOT=relative')
            self.assertIn(f'output={root}/relative/macOS/release', parent)
            self.assertIn(f'output={root}/relative/macOS/release', child)
            self.make(root, 'release', f'BUILD_ROOT={self.root}/absolute-{name}')
            self.assertTrue((self.root / f'absolute-{name}/macOS/release/Fixture/Fixture.zip').exists())

    def test_foreign_workdir_roots_clean_scopes_and_variants(self):
        root = self.fixture('daemon')
        for entry in (root / 'Makefile', root / 'source/Makefile'):
            out = self.make(self.root, '-f', str(entry), 'release', 'BUILD_ROOT=custom')
            self.assertTrue((root / 'custom/macOS/release/Fixture/Fixture.zip').is_file(), out)
        self.make(root, 'release', 'BUILD_VARIANT=alternative', 'BUILD_FLAGS=-DOTHER=1')
        self.assertTrue((root / 'build/macOS/release/variants/alternative/Fixture/Fixture.zip').is_file())
        self.make(root, 'release')
        helper = root / 'build/macOS/release/helper/helper'
        self.assertTrue(helper.is_file())
        self.make(root, 'clean', 'PRODUCT=Fixture')
        self.assertTrue(helper.is_file())
        self.assertFalse((root / 'build/macOS/release/Fixture').exists())
        self.assertFalse((root / 'build/macOS/release/variants/alternative/Fixture').exists())
        self.make(root, 'clean-all')
        self.assertFalse((root / 'build').exists())
        for override in ('', '/', str(root), 'with space'):
            self.make(root, 'release', 'BUILD_ROOT=' + override, good=False)
        self.make(root, 'clean', 'PRODUCT=../source', good=False)
        self.assertTrue((root / 'source/main.c').is_file())

    def test_colliding_basenames_and_case_insensitive_product_names(self):
        root = self.fixture('products')
        nested = root / 'source/nested'
        nested.mkdir()
        (nested / 'main.c').write_text('int second(void) { return 0; }')
        self.make(root, 'release', 'Fixture_SOURCES=main.c nested/main.c')
        objects = list((root / 'build/macOS/release/Fixture/Intermediates').rglob('main.c.o'))
        self.assertEqual(len(objects), 8)
        self.assertTrue((root / 'build/macOS/release/libsupport/libsupport.a').exists())
        self.make(root, 'release', 'support_OUTPUT_NAME=fixture', good=False)
        self.make(root, 'release', 'Fixture_OUTPUT_NAME=../source', good=False)

    def test_redirected_outputs_and_owned_roots(self):
        root = self.fixture('simple')
        self.make(root, 'release')
        config = root / 'build/macOS/release'
        shutil.rmtree(config)
        config.symlink_to(root / 'source', target_is_directory=True)
        self.make(root, 'release', good=False)
        self.assertFalse((root / 'source/Fixture').exists())
        self.make(root, 'clean')
        other = self.fixture('daemon')
        self.make(other, 'release', 'BUILD_ROOT=' + str(root / 'build'), good=False)
        self.make(root, 'release', 'BUILD_VARIANT=../bad', good=False)

    def test_analyzer_uses_build_root_and_preserves_source_paths(self):
        root = self.fixture('simple')
        (root / 'source/nested').mkdir()
        (root / 'source/nested/main.c').write_text('int second(void) { return 0; }')
        self.make(root, 'analyze', 'BUILD_ROOT=reports', f'ANALYZER={self.tool}',
                  'Fixture_SOURCES=main.c nested/main.c')
        reports = list((root / 'reports/analyze/macOS/Fixture').rglob('*.plist'))
        self.assertEqual(len(reports), 2)
        self.make(root, 'clean', 'BUILD_ROOT=reports', 'PRODUCT=Fixture')
        self.assertFalse((root / 'reports/analyze/macOS/Fixture').exists())

    @unittest.skipUnless(shutil.which('clang'), 'host analysis requires Clang')
    def test_host_analyzer_uses_native_target(self):
        root = self.fixture('simple')
        self.make(root, 'analyze', 'PLATFORM=host',
                  'Fixture_TYPE=executable', f'ANALYZER={shutil.which("clang")}')
        reports = list((root / 'build/analyze/linux/Fixture').rglob('*.plist'))
        self.assertEqual(len(reports), 1)

    def test_host_package_validation_does_not_use_apple_lipo(self):
        root = self.fixture('simple')
        self.make(root, 'release', 'validate-package', 'PLATFORM=host',
                  'Fixture_TYPE=executable', 'LIPO=/nonexistent/apple-lipo')
        self.assertTrue((root / 'build/linux/release/Fixture/Fixture.zip').is_file())

    def test_parallel_root_claims_publish_complete_identity(self):
        root = self.fixture('simple')
        identity = 'parallel-project-identity'
        (root / '.altivec-project').write_text(identity)
        command = ['python3', str(ROOT / 'make/build.py'), 'safe-root',
                   str(root), str(root / 'build')]
        processes = [subprocess.Popen(command, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE) for _ in range(16)]
        for process in processes:
            _, error = process.communicate()
            self.assertEqual(process.returncode, 0, error)
        marker = root / 'build/.altivec-build-root'
        self.assertEqual(marker.read_text(), identity)
        self.assertFalse(list((root / 'build').glob('.altivec-owner-*')))

    def test_mutex_released_between_mkdir_and_inspection(self):
        import importlib.util
        from unittest.mock import patch
        spec = importlib.util.spec_from_file_location('mutex_helper', ROOT / 'make/build.py')
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        lock = self.root / 'racing-lock'
        original = Path.mkdir
        raced = False

        def mkdir(path, *args, **kwargs):
            nonlocal raced
            if path == lock and not raced:
                raced = True
                # The owner released it before the following lstat.
                raise FileExistsError()
            return original(path, *args, **kwargs)

        with patch.object(Path, 'mkdir', mkdir):
            with helper.directory_mutex(lock):
                self.assertTrue((lock / 'owner.json').is_file())
        self.assertFalse(lock.exists())

    def test_clean_waits_for_active_build(self):
        root = self.fixture('simple')
        self.make(root, 'release')
        import importlib.util
        spec = importlib.util.spec_from_file_location('build_helper', ROOT / 'make/build.py')
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        code = ("import sys; from pathlib import Path; "
                f"sys.path.insert(0, {str(ROOT / 'make')!r}); from build import clean; "
                f"Path({str(self.root / 'ready')!r}).touch(); "
                f"clean({str(root)!r}, {str(root / 'build')!r}, '--all')")
        with helper.build_lock(root / 'build'):
            child = subprocess.Popen(['python3', '-c', code])
            deadline = time.monotonic() + 10
            while not (self.root / 'ready').exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue((self.root / 'ready').exists())
            time.sleep(0.1)
            self.assertIsNone(child.poll())
            self.assertTrue((root / 'build').is_dir())
        self.assertEqual(child.wait(timeout=10), 0)
        self.assertFalse((root / 'build').exists())

    def test_incremental_headers_resources_flags_and_removed_resources(self):
        root = self.fixture('simple')
        self.make(root, 'release')
        objects = list((root / 'build').rglob('*.o'))
        first = {p: p.stat().st_mtime_ns for p in objects}
        self.make(root, 'release')
        self.assertEqual(first, {p: p.stat().st_mtime_ns for p in objects})
        time.sleep(1.05)
        (root / 'source/value.h').write_text('#define VALUE 1\n')
        self.make(root, 'release')
        self.assertTrue(all(p.stat().st_mtime_ns > first[p] for p in objects))
        second = {p: p.stat().st_mtime_ns for p in objects}
        time.sleep(1.05)
        (root / 'source/message.txt').write_text('changed\n')
        self.make(root, 'release')
        self.assertEqual(second, {p: p.stat().st_mtime_ns for p in objects})
        with zipfile.ZipFile(root / 'build/macOS/release/Fixture/Fixture.zip') as z:
            self.assertEqual(z.read('Fixture.app/Contents/Resources/message.txt'), b'changed\n')
        self.make(root, 'release', 'Fixture_RESOURCES=')
        with zipfile.ZipFile(root / 'build/macOS/release/Fixture/Fixture.zip') as z:
            self.assertNotIn('Fixture.app/Contents/Resources/message.txt', z.namelist())
        self.make(root, 'release', 'BUILD_FLAGS=-DCHANGED=1')
        self.assertTrue(all(p.stat().st_mtime_ns > second[p] for p in objects))

    def test_architecture_subset_and_reject_wrong_library(self):
        root = self.fixture('simple')
        self.make(root, 'release', 'ARCHS=ppc i386')
        self.assertEqual((root / 'build/macOS/release/Fixture/Fixture').read_text(), '["i386", "ppc"]')
        self.make(root, 'release', 'ARCHS=arm64')
        self.assertEqual((root / 'build/macOS/release/Fixture/Fixture').read_text(), '["arm64"]')
        lib = self.root / 'wrong.a'
        lib.write_text('["ppc"]')
        self.make(root, 'release', 'ARCHS=arm64', f'Fixture_STATIC_LIBS={lib}', good=False)

    def test_clean_cannot_erase_source(self):
        root = self.fixture('simple')
        for unsafe in (root, root.parent, root / 'source', Path('/')):
            self.make(root, 'clean', f'BUILD_ROOT={unsafe}', good=False)
        self.assertTrue((root / 'source/main.c').exists())
        outside = self.root / 'other-project'
        outside.mkdir()
        (outside / 'main.c').write_text('int main(void) { return 0; }')
        self.make(root, 'clean', f'BUILD_ROOT={outside}', good=False)
        self.make(root, 'release')
        shutil.rmtree(root / 'build/macOS')
        (root / 'build/macOS').symlink_to(root / 'source', target_is_directory=True)
        self.make(root, 'clean')
        self.assertTrue((root / 'source/main.c').exists())
        self.assertFalse((root / 'build/macOS').exists())

    def test_nested_resource_maps_and_package_resources(self):
        root = self.fixture('simple')
        nested = root / 'source/nested'
        nested.mkdir()
        (nested / 'value.txt').write_text('first')
        (nested / 'value.txt').chmod(0o600)
        args = ('release', 'Fixture_RESOURCE_MAP=nested=Nested',
                'Fixture_PACKAGE_RESOURCES=nested=Extra')
        self.make(root, *args)
        time.sleep(1.05)
        (nested / 'value.txt').write_text('second')
        self.make(root, *args)
        with zipfile.ZipFile(root / 'build/macOS/release/Fixture/Fixture.zip') as z:
            self.assertEqual(z.read('Fixture.app/Contents/Resources/Nested/value.txt'), b'second')
            self.assertEqual(z.read('Extra/value.txt'), b'second')
            self.assertEqual((z.getinfo('Extra/value.txt').external_attr >> 16) & 0o777, 0o644)
            self.assertEqual((z.getinfo('Fixture.app/Contents/Resources/Nested/value.txt').external_attr >> 16) & 0o777, 0o644)
        (nested / 'value.txt').unlink()
        self.make(root, *args)
        with zipfile.ZipFile(root / 'build/macOS/release/Fixture/Fixture.zip') as z:
            self.assertNotIn('Extra/value.txt', z.namelist())

    def test_generated_input_parallel_configs(self):
        root = self.fixture('simple')
        manifest = root / 'source/Makefile'
        text = manifest.read_text()
        generator = ("GENERATORS = value\nGEN_value_OUTPUT = generated.h\n"
                     "GEN_value_INPUTS = value.h\n"
                     "GEN_value_COMMAND = sleep 1; cp value.h generated.h; echo run >> generated.log\n"
                     "Fixture_GENERATED = generated.h\n")
        manifest.write_text(generator + text)
        (root / 'source/main.c').write_text('#include "generated.h"\nint main(void) { return VALUE; }\n')
        self.make(root, '-j4', 'debug', 'release')
        self.assertEqual((root / 'source/generated.log').read_text().splitlines(), ['run'])
        self.make(root, 'release', 'CONFIG=../source', good=False)

    @unittest.skipUnless(shutil.which('dpkg-deb'), 'Debian packaging runs inside the offline container')
    def test_rootless_keeps_container_policy(self):
        root = self.fixture('simple')
        self.make(root, 'release', 'PLATFORM=phone', 'Fixture_PACKAGES=deb-rootless',
                  'Fixture_PACKAGE_ARCH=all', 'Fixture_PACKAGE_ID=org.altivec.fixture',
                  'Fixture_VERSION=1.0', 'Fixture_SANDBOX=container')
        archive = root / 'build/iOS/release/Fixture/Fixture-rootless.deb'
        destination = self.root / 'extracted'
        subprocess.run(['dpkg-deb', '-x', str(archive), str(destination)], check=True)
        self.assertTrue((destination / 'var/jb/Applications/Fixture.app/Fixture').exists())
        self.make(root, 'validate', 'PLATFORM=phone', 'Fixture_SANDBOX=unsandboxed', good=False)

    def test_phone_ipa_and_arc_policy(self):
        root = self.fixture('simple')
        self.make(root, 'release', 'PLATFORM=phone')
        with zipfile.ZipFile(root / 'build/iOS/release/Fixture/Fixture.ipa') as z:
            self.assertIn('Payload/Fixture.app/Fixture', z.namelist())
        self.make(root, 'release', 'Fixture_GROUPS=ui', 'GROUP_ui_MEMORY=arc', good=False)


if __name__ == '__main__':
    unittest.main()
