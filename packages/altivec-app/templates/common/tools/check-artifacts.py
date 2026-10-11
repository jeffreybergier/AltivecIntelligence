#!/usr/bin/env python3
"""Inspect generated packages after shared Make's slice/signing/DEB validation."""
import json
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
META = json.loads((ROOT / '.altivec-template.json').read_text())
CPUS = {7: 'i386', 18: 'ppc', 0x1000007: 'x86_64', 12: 'armv7', 0x100000c: 'arm64'}


def macho(data, platform):
    magic = data[:4]
    if magic == b'\xca\xfe\xba\xbe':
        count = struct.unpack_from('>I', data, 4)[0]
        assert 0 < count <= 8, 'Invalid fat slice count'
        recognized = False
        for i in range(count):
            _, _, offset, size, _ = struct.unpack_from('>5I', data, 8 + i * 20)
            assert offset + size <= len(data), 'Truncated fat slice'
            recognized = macho(data[offset:offset + size], platform) or recognized
        return recognized
    formats = {b'\xce\xfa\xed\xfe': ('<', 28), b'\xcf\xfa\xed\xfe': ('<', 32),
               b'\xfe\xed\xfa\xce': ('>', 28), b'\xfe\xed\xfa\xcf': ('>', 32)}
    if magic not in formats:
        return False
    endian, offset = formats[magic]
    cpu = CPUS[struct.unpack_from(endian + 'I', data, 4)[0]]
    commands = struct.unpack_from(endian + 'I', data, 16)[0]
    expected = {'ppc': (10, 4), 'i386': (10, 4), 'x86_64': (10, 9),
                'armv7': (5, 0), 'arm64': (11, 0) if platform == 'macOS' else (7, 0)}[cpu]
    floor = None
    for _ in range(commands):
        cmd, size = struct.unpack_from(endian + 'II', data, offset)
        assert size >= 8 and offset + size <= len(data), 'Truncated load command'
        if cmd in (0x24, 0x25, 0x32):
            version = struct.unpack_from(endian + 'I', data, offset + (12 if cmd == 0x32 else 8))[0]
            floor = (version >> 16, (version >> 8) & 255)
        if cmd in (0xc, 0x80000018, 0x8000001f, 0x20, 0x80000023):
            start = struct.unpack_from(endian + 'I', data, offset + 8)[0]
            dependency = data[offset + start:offset + size].split(b'\0')[0].decode()
            assert dependency.startswith(('/usr/lib/', '/System/Library/')), dependency
        offset += size
    # Tiger's legacy linker can omit the minimum-version load command.
    assert floor == expected or (cpu in ('ppc', 'i386') and floor is None), (cpu, floor, expected)
    return True


def main():
    release = json.loads((ROOT / '.altivec-release.json').read_text())
    count = 0
    for config in ('debug', 'release'):
        for target in release['targets']:
            for entry in target['artifacts']:
                archive = ROOT / entry['path'].replace('/release/', '/' + config + '/')
                if not archive.exists():
                    raise ValueError(f'Build {config} before artifact inspection: {archive}')
                with tempfile.TemporaryDirectory(prefix='altivec-artifact-') as temporary:
                    dest = Path(temporary)
                    if archive.suffix == '.deb':
                        subprocess.run(['dpkg-deb', '-x', str(archive), str(dest)], check=True)
                    else:
                        with zipfile.ZipFile(archive) as z:
                            assert z.testzip() is None
                            for name in z.namelist():
                                assert not name.startswith('/') and '..' not in Path(name).parts
                            z.extractall(dest)
                    for file in dest.rglob('*'):
                        if not file.is_file():
                            continue
                        data = file.read_bytes()
                        if file.name == 'Info.plist':
                            info = plistlib.loads(data)
                            assert info['CFBundleIdentifier'] == META['bundle_id']
                            resources = file.parent / 'Resources' if target['name'] == 'macOS' else file.parent
                            for icon in info.get('CFBundleIconFiles', []):
                                assert (resources / icon).is_file(), icon
                            if 'CFBundleIconFile' in info:
                                assert (resources / info['CFBundleIconFile']).is_file()
                        if target['name'] != 'linux':
                            if macho(data, target['name']):
                                nm = shutil.which('llvm-nm') or shutil.which('nm')
                                symbols = subprocess.check_output([nm, str(file)], text=True)
                                assert '_main' in symbols, file
                    if archive.name == 'model.zip':
                        assert (dest / 'include/model.h').is_file()
                        assert (dest / 'LICENSE').is_file()
                        nm = shutil.which('llvm-nm') or shutil.which('nm')
                        symbols = subprocess.check_output([nm, str(dest / 'lib/libmodel.a')], text=True)
                        assert 'model_add' in symbols and 'model_version' in symbols
                        if target['name'] == 'linux':
                            consumer = dest / 'consumer'
                            subprocess.run(['cc', '-I' + str(dest / 'include'),
                                            str(ROOT / 'tests/consumer.c'),
                                            str(dest / 'lib/libmodel.a'), '-o', str(consumer)], check=True)
                            subprocess.run([str(consumer)], check=True)
                count += 1
    print(f'PASS: {count} archives; deployment floors, dynamic dependencies, resources and public symbols')


if __name__ == '__main__':
    main()
