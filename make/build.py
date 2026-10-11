#!/usr/bin/env python3
"""Portable filesystem/packaging operations used by the Make product modules."""
import argparse
import contextlib
import hashlib
import json
import socket
import time
import uuid
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def safe_root(project, root, create=True):
    if not project or not root or any(c.isspace() for c in project + root):
        raise ValueError('PROJECT_ROOT and BUILD_ROOT must be nonempty paths without whitespace')
    project, root = Path(project).resolve(), Path(root).resolve()
    if root == Path('/') or root == Path.home() or root == project or root in project.parents:
        raise ValueError('BUILD_ROOT must be a dedicated output directory')
    if root.is_relative_to(project) and root.relative_to(project).parts[0] in (
            'source', 'src', '.git', '.agents', '.codex', 'apps', 'libs', 'make', 'test', 'tests', 'toolchain'):
        raise ValueError('BUILD_ROOT must not be a source or metadata directory')
    marker = root / '.altivec-build-root'
    if marker.is_symlink():
        raise ValueError('Build ownership marker must not be a symlink')
    project_marker = project / '.altivec-project'
    identity = project_marker.read_text().strip() if project_marker.is_file() else str(project)
    # Older engines recorded mount-specific absolute paths. Upgrade their
    # already-owned output trees on the next write; new markers are portable.
    if marker.is_file():
        previous = marker.read_text()
        legacy = previous == str(project) or (previous.startswith('/')
                 and Path(previous).name == project.name)
        if previous != identity and not legacy:
            raise ValueError('BUILD_ROOT belongs to another project')
    owned = marker.is_file()
    if root.exists():
        if shutil.which('git'):
            check = subprocess.run(['git', '-C', str(project), 'ls-files', '--', str(root)],
                                   capture_output=True, text=True)
            if check.returncode == 0 and check.stdout.strip():
                raise ValueError('BUILD_ROOT contains tracked project files')
        if not owned:
            for p in root.rglob('*'):
                if any(part.endswith(('.app', '.framework')) for part in p.parts):
                    continue
                if p.name in ('.git', 'Makefile', 'AGENTS.md', 'CMakeLists.txt', 'package.json') or p.suffix in ('.c', '.m', '.mm', '.cc', '.cpp', '.cxx', '.h', '.hh', '.hpp', '.mk', '.py', '.js', '.swift', '.rs', '.go'):
                    raise ValueError(f'BUILD_ROOT contains source: {p}')
    if create:
        root.mkdir(parents=True, exist_ok=True)
        marker.write_text(identity)
    return root


def lock_owner():
    return json.dumps({'host': socket.gethostname(), 'pid': os.getpid()})


def owner_finished(path):
    # Only our own PID namespace can safely establish that an owner has exited.
    try:
        owner = json.loads(path.read_text())
        if owner['host'] != socket.gethostname():
            return False
        os.kill(owner['pid'], 0)
    except ProcessLookupError:
        return True
    except (OSError, ValueError, KeyError):
        pass
    return False


@contextlib.contextmanager
def directory_mutex(path):
    # Atomic mkdir coordinates Linux containers and their macOS host. flock
    # does not cross Docker Desktop's host/guest boundary reliably.
    while True:
        try:
            path.mkdir()
            break
        except FileExistsError:
            if path.is_symlink() or not path.is_dir():
                raise ValueError(f'Unsafe build lock: {path}')
            time.sleep(0.05)
    try:
        (path / 'owner.json').write_text(lock_owner())
        yield
    finally:
        (path / 'owner.json').unlink()
        path.rmdir()


@contextlib.contextmanager
def build_lock(root, scope='', exclusive=False):
    # Sibling metadata survives clean-all and is shared by host/container mounts.
    root = Path(root).resolve()
    if scope and Path(scope).is_absolute():
        scope = str(Path(scope).resolve().relative_to(root))
    directory = root.parent / ('.' + root.name + '.altivec-locks')
    if directory.is_symlink():
        raise ValueError('Build lock directory must not be a symlink')
    directory.mkdir(parents=True, exist_ok=True)
    if scope:
        with directory_mutex(directory / hashlib.sha256(scope.encode()).hexdigest()):
            yield
        return
    readers = directory / 'readers'
    if readers.is_symlink():
        raise ValueError('Build reader directory must not be a symlink')
    readers.mkdir(exist_ok=True)
    writer, gate = directory / 'writer', directory / 'gate'
    if exclusive:
        with directory_mutex(writer):
            # Finish any reader registration that raced the writer marker.
            with directory_mutex(gate):
                pass
            while list(readers.iterdir()):
                for reader in readers.iterdir():
                    if owner_finished(reader):
                        reader.unlink(missing_ok=True)
                time.sleep(0.05)
            yield
    else:
        token = readers / (uuid.uuid4().hex + '.json')
        while True:
            with directory_mutex(gate):
                if not writer.exists():
                    token.write_text(lock_owner())
                    break
            time.sleep(0.05)
        try:
            yield
        finally:
            token.unlink()


def remove_output(path):
    if path.is_symlink():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def clean(project, root, platform, product=None):
    safe_root(project, root, create=False)
    with build_lock(root, exclusive=True):
        root = safe_root(project, root)
        if platform == '--all':
            remove_output(root)
            return
        if not re.fullmatch(r'[A-Za-z0-9_-]+', platform):
            raise ValueError('Invalid clean platform')
        if product and not re.fullmatch(r'[A-Za-z0-9_-]+', product):
            raise ValueError('Invalid clean product')
        if product:
            base = root / platform
            if base.is_symlink():
                raise ValueError('Cannot clean a product through a platform symlink')
            for configuration in ('debug', 'release'):
                config = base / configuration
                if config.is_symlink():
                    raise ValueError('Cannot clean a product through a configuration symlink')
                remove_output(config / product)
                variants = config / 'variants'
                if variants.is_symlink():
                    raise ValueError('Cannot clean through a variants symlink')
                if variants.is_dir():
                    for variant in variants.iterdir():
                        if variant.is_dir() and not variant.is_symlink():
                            remove_output(variant / product)
            analysis = root / 'analyze'
            if analysis.is_symlink() or (analysis / platform).is_symlink():
                raise ValueError('Cannot clean through an analyzer symlink')
            remove_output(analysis / platform / product)
            variants = analysis / platform / 'variants'
            if variants.is_symlink():
                raise ValueError('Cannot clean through a variants symlink')
            if variants.is_dir():
                for variant in variants.iterdir():
                    if variant.is_dir() and not variant.is_symlink():
                        remove_output(variant / product)
        else:
            remove_output(root / platform)
            for category in ('analyze', 'tests', 'dependencies'):
                parent = root / category
                if parent.is_symlink():
                    raise ValueError('Cannot clean through a category symlink')
                remove_output(parent / platform)


def copy(src, dst):
    src, dst = Path(src), Path(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        shutil.copytree(src, dst, symlinks=True, dirs_exist_ok=True)
    else:
        shutil.copy2(src, dst)


def normalize_modes(root):
    # Downloaded/generated inputs may be owner-only. Installed resources must
    # remain readable, while binaries and scripts retain executable permission.
    for path in Path(root).rglob('*'):
        if not path.is_symlink():
            path.chmod(0o755 if path.is_dir() or path.stat().st_mode & 0o111 else 0o644)


def child(root, path):
    path = Path(path)
    if path.is_absolute() or '..' in path.parts:
        raise ValueError(f'Unsafe destination: {path}')
    return root / path


def bundle(a):
    dest = Path(a.output)
    temporary = dest.with_suffix('.app.tmp')
    shutil.rmtree(temporary, ignore_errors=True)
    mac = a.platform == 'macOS'
    resources = temporary / ('Contents/Resources' if mac else '')
    resources.mkdir(parents=True)
    copy(a.binary, temporary / ('Contents/MacOS' if mac else '') / a.name)
    copy(a.plist, temporary / ('Contents' if mac else '') / 'Info.plist')
    for src in a.resource:
        copy(src, resources / Path(src).name)
    for src in a.font:
        copy(src, resources / 'Fonts' / Path(src).name)
    for src in a.localization:
        paths = [Path(src)] if src.endswith('.lproj') else Path(src).glob('*.lproj')
        for p in paths:
            copy(p, resources / p.name)
            if mac:
                for f in (resources / p.name).glob('*.strings'):
                    data = f.read_bytes()
                    if not data.startswith((b'\xff\xfe', b'\xfe\xff')):
                        f.write_bytes(data.decode('utf-8-sig').encode('utf-16'))
    for mapping in a.map:
        src, dst = mapping.split('=', 1)
        copy(src, child(resources, dst))
    for mapping in a.embed:
        src, dst = mapping.split('=', 1)
        copy(src, child(temporary, dst))
    for src in a.framework:
        copy(src, temporary / 'Contents/Frameworks' / Path(src).name)
    (temporary / ('Contents' if mac else '') / 'PkgInfo').write_bytes(b'APPL????')
    for excluded in a.exclude:
        path = child(resources, excluded)
        if path.is_dir():
            shutil.rmtree(path)
        elif path.exists():
            path.unlink()
    normalize_modes(temporary)
    shutil.rmtree(dest, ignore_errors=True)
    temporary.rename(dest)


def package(a):
    output = Path(a.output).absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent, prefix='.package-') as directory:
        stage = Path(directory)
        src = Path(a.input)
        if a.format in ('zip', 'ipa'):
            root = stage / 'Payload' if a.format == 'ipa' else stage
            copy(src, child(root, a.main_path or src.name))
            for mapping in a.extra:
                source, target = mapping.split('=', 1)
                copy(source, child(root, target))
            normalize_modes(stage)
            entries = sorted(p.name for p in stage.iterdir())
            archive = stage / 'archive.zip'
            run('zip', '-rqy', str(archive), *entries, cwd=stage)
            os.replace(archive, output)
            return
        if a.format not in ('deb-rootful', 'deb-rootless'):
            raise ValueError(f'Unknown package format: {a.format}')
        if a.architecture not in ('all', 'iphoneos-arm', 'iphoneos-arm64'):
            raise ValueError('Declare PACKAGE_ARCH as all, iphoneos-arm, or iphoneos-arm64')
        if not a.package_id or not a.version:
            raise ValueError('Debian packages require PACKAGE_ID and VERSION')
        if src.suffix == '.app':
            info = plistlib.loads((src / 'Info.plist').read_bytes())
            if info.get('CFBundleShortVersionString') != a.version:
                raise ValueError('Debian version differs from the app plist version')
        prefix = a.prefix.lstrip('/')
        if '..' in Path(prefix).parts:
            raise ValueError('Unsafe install prefix')
        root = stage / 'root'
        destination = child(root, prefix) / ('Applications' if src.suffix == '.app' else 'usr/libexec') / src.name
        copy(src, destination)
        executable_paths = [destination / a.name if src.suffix == '.app' else destination]
        for mapping in a.install:
            source, target = mapping.split('=', 1)
            target = child(child(root, prefix), target)
            copy(source, target)
            executable_paths.append(target)
        for source in a.launchd:
            target = child(root, prefix) / 'Library/LaunchDaemons' / Path(source).name.removesuffix('.in')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(Path(source).read_text().replace('@PREFIX@', a.prefix))
        for mapping in a.package_file:
            source, target = mapping.split('=', 1)
            copy(source, child(child(root, prefix), target))
        control = root / 'DEBIAN'
        control.mkdir(parents=True)
        values = {'Package': a.package_id, 'Name': a.name, 'Version': a.version,
                  'Architecture': a.architecture, 'Section': 'Applications', 'Priority': 'optional',
                  'Maintainer': a.maintainer, 'Description': a.description}
        if any('\n' in value for value in values.values()):
            raise ValueError('Package metadata must be single-line')
        (control / 'control').write_text(''.join(f'{key}: {value}\n' for key, value in values.items()))
        for source in a.script:
            name = Path(source).name.removesuffix('.in')
            if name not in ('preinst', 'postinst', 'prerm', 'postrm'):
                raise ValueError(f'Invalid lifecycle script: {name}')
            text = Path(source).read_text()
            if a.lifecycle:
                text = text.replace('# ALTIVEC_LIFECYCLE', Path(a.lifecycle).read_text()).replace('# RC_LIFECYCLE', Path(a.lifecycle).read_text())
            text = text.replace('@PREFIX@', a.prefix)
            text = text.replace('set -e', 'export PATH=' + a.prefix + '/usr/sbin:' + a.prefix + '/usr/bin:' + a.prefix + '/sbin:' + a.prefix + '/bin:/usr/sbin:/usr/bin:/sbin:/bin\nset -e', 1)
            (control / name).write_text(text)
            executable_paths.append(control / name)
        for p in root.rglob('*'):
            if not p.is_symlink():
                p.chmod(0o755 if p.is_dir() or p.stat().st_mode & 0o111 else 0o644)
        for p in executable_paths:
            p.chmod(0o755)
        if a.owner != '0:0':
            raise ValueError('Only explicit root ownership (0:0) is currently supported')
        archive = stage / 'archive.deb'
        run('dpkg-deb', '--root-owner-group', '-Z' + a.compression, '--build', str(root), str(archive))
        os.replace(archive, output)


def validate(paths):
    for path in paths:
        p = Path(path)
        if p.suffix == '.deb':
            run('dpkg-deb', '--info', str(p))
            run('dpkg-deb', '--contents', str(p), stdout=subprocess.DEVNULL)
        else:
            with zipfile.ZipFile(p) as z:
                if z.testzip():
                    raise ValueError(f'Corrupt archive: {p}')
                names = z.namelist()
                if p.suffix == '.ipa' and not any(n.startswith('Payload/') and n.endswith('/Info.plist') for n in names):
                    raise ValueError('IPA is missing app Info.plist')
                for n in names:
                    if n.endswith('/Info.plist'):
                        plistlib.loads(z.read(n))
        print(f'Validated {p}')


def validate_one(a):
    archive = Path(a.output)
    with tempfile.TemporaryDirectory(prefix='altivec-validate-') as temp:
        root = Path(temp)
        if a.format.startswith('deb-'):
            architecture = subprocess.check_output(['dpkg-deb', '-f', str(archive), 'Architecture'], text=True).strip()
            if architecture != a.architecture:
                raise ValueError('Package architecture differs from declared policy')
            run('dpkg-deb', '-x', str(archive), str(root))
            run('dpkg-deb', '-e', str(archive), str(root / 'DEBIAN'))
            import io
            data = subprocess.check_output(['dpkg-deb', '--fsys-tarfile', str(archive)])
            with tarfile.open(fileobj=io.BytesIO(data)) as tar:
                if any(m.uid != 0 or m.gid != 0 for m in tar):
                    raise ValueError('Package payload does not have declared root ownership')
            for script in (root / 'DEBIAN').iterdir():
                if script.name != 'control':
                    run('sh', '-n', str(script))
            prefix = root / a.prefix.lstrip('/')
            for launchd in (prefix / 'Library/LaunchDaemons').glob('*.plist'):
                values = plistlib.loads(launchd.read_bytes())
                program = values.get('Program') or values.get('ProgramArguments', [''])[0]
                if program and not (root / program.lstrip('/')).is_file():
                    raise ValueError(f'Launchd executable missing from package: {program}')
        else:
            with zipfile.ZipFile(archive) as z:
                if z.testzip():
                    raise ValueError('Corrupt ZIP member')
                for n in z.namelist():
                    child(root, n)
                z.extractall(root)
        for check in a.binary_check:
            relative, entitlements = check.split('|', 1)
            binary = child(root, relative)
            if not binary.is_file():
                raise ValueError(f'Package executable missing: {relative}')
            for arch in a.arch:
                run(a.lipo, str(binary), '-verify_arch', arch)
            if entitlements:
                expected = plistlib.loads(Path(entitlements).read_bytes())
                for arch in a.arch:
                    # Tiger slices remain untouched; code-signing policy applies
                    # to the modern Mac slices and every supported iOS slice.
                    if a.platform == 'macOS' and arch not in ('x86_64', 'arm64'):
                        continue
                    thin = root / ('.entitlements-' + arch)
                    if len(a.arch) == 1:
                        shutil.copy2(binary, thin)
                    else:
                        run(a.lipo, str(binary), '-thin', arch, '-output', str(thin))
                    raw = subprocess.check_output([a.ldid, '-e', str(thin)])
                    parts = re.findall(rb'<\?xml.*?</plist>', raw, re.S)
                    if len(parts) != 1 or plistlib.loads(parts[0]) != expected:
                        raise ValueError(f'Entitlements differ for {relative} ({arch})')

        for plist in root.rglob('Info.plist'):
            plistlib.loads(plist.read_bytes())
        print(f'Validated architecture, metadata, ownership, lifecycle and executable entitlements: {archive}')


def main():
    command, *args = sys.argv[1:]
    if command == 'names':
        if len(set(name.casefold() for name in args)) != len(args):
            raise ValueError('Product output directories collide ignoring case; set <product>_OUTPUT_NAME')
        for name in args:
            if not re.fullmatch(r'[A-Za-z0-9_-]+', name) or name == 'variants':
                raise ValueError(f'Invalid product name: {name}; use letters, digits, underscores and hyphens (variants is reserved)')
    elif command == 'check-root':
        safe_root(*args, create=False)
    elif command == 'guard':
        project, root, scope, *invocation = args
        safe_root(project, root, create=False)
        # Refuse redirected output ancestors before Make creates any stamp.
        canonical = Path(root).resolve()
        destination = Path(root) / scope
        if not destination.resolve().is_relative_to(canonical):
            raise ValueError('Output directory must remain inside BUILD_ROOT')
        paths = [destination, *destination.parents]
        if destination.is_dir():
            paths.extend(p for p in destination.rglob('*') if p.is_symlink())
        for path in paths:
            if path == Path(root) or path in Path(root).parents:
                continue
            if path.is_symlink() and not path.resolve().is_relative_to(canonical):
                raise ValueError(f'Output ancestor escapes BUILD_ROOT: {path}')
        with build_lock(root), build_lock(root, scope, exclusive=True):
            safe_root(project, root)
            # Preserve GNU Make's jobserver descriptors for recursive builds.
            raise SystemExit(subprocess.call(invocation, close_fds=False))
    elif command == 'stamp':
        path, *values = args
        p = Path(path)
        data = '\n'.join(values) + '\n'
        if not p.exists() or p.read_text() != data:
            p.parent.mkdir(parents=True, exist_ok=True)
            tmp = p.with_name(p.name + '.' + str(os.getpid()) + '.tmp')
            tmp.write_text(data)
            if p.exists():
                previous = p.stat().st_mtime_ns
                while time.time_ns() // 1_000_000_000 <= previous // 1_000_000_000:
                    time.sleep(0.02)
            tmp.touch()
            tmp.replace(p)
    elif command == 'generate':
        output, command_line, *inputs = args
        path = Path(output).resolve()
        with build_lock(path, 'generator', exclusive=True):
            state = path.with_name(path.name + '.altivec-generator')
            signature = hashlib.sha256((command_line + '\n' + '\n'.join(inputs)).encode()).hexdigest()
            if (path.exists() and state.is_file() and state.read_text() == signature
                    and all(Path(p).stat().st_mtime_ns <= path.stat().st_mtime_ns for p in inputs)):
                return
            subprocess.run(command_line, shell=True, check=True)
            if not path.is_file():
                raise ValueError(f'Generator did not create {path}')
            state.write_text(signature)
    elif command == 'inputs':
        for src in args:
            p = Path(src)
            print(p)
            if p.is_dir():
                print(' '.join(str(f) for f in sorted(p.rglob('*'))))
    elif command == 'slices':
        lipo, arch, *libraries = args
        if arch == 'host':
            return
        for library in libraries:
            run(lipo, library, '-verify_arch', arch)
    elif command == 'policy':
        policy, entitlements = args
        if policy not in ('', 'container', 'unsandboxed'):
            raise ValueError('SANDBOX must be container or unsandboxed')
        values = plistlib.loads(Path(entitlements).read_bytes()) if entitlements else {}
        if policy == 'container' and (values.get('com.apple.private.security.no-sandbox') or
                                      values.get('com.apple.private.security.no-container') or
                                      values.get('com.apple.private.security.container-required') is False):
            raise ValueError('Container sandbox policy conflicts with executable entitlements')
        if policy == 'unsandboxed' and not values.get('com.apple.private.security.no-sandbox'):
            raise ValueError('Unsandboxed policy requires explicit no-sandbox entitlement')
    elif command == 'floor':
        platform, arch, minimum = args
        if arch == 'host':
            return
        number = tuple(int(v) for v in minimum.split('.'))
        floor = {'ppc': (10, 4), 'i386': (10, 4), 'x86_64': (10, 9),
                 'armv7': (5, 0), 'arm64': (11, 0) if platform == 'macOS' else (7, 0)}[arch]
        if number < floor:
            raise ValueError(f'{arch} minimum {minimum} is below supported floor {floor}')
    elif command == 'mac-sign':
        binary, lipo, identifier, plist, pem, entitlements = args
        info = subprocess.check_output([lipo, binary, '-info'], text=True)
        architectures = info.split(' are: ')[-1].split(' architecture: ')[-1].split()
        with tempfile.TemporaryDirectory() as temp:
            slices = []
            for arch in architectures:
                thin = str(Path(temp) / arch)
                if len(architectures) == 1:
                    shutil.copy2(binary, thin)
                else:
                    run(lipo, binary, '-thin', arch, '-output', thin)
                if arch in ('x86_64', 'arm64'):
                    flags = ['--timestamp-url', 'none']
                    if entitlements:
                        flags += ['--entitlements-xml-file', entitlements]
                    if identifier:
                        flags += ['--binary-identifier', identifier]
                    if plist:
                        flags += ['--info-plist-file', plist]
                    if pem:
                        flags += ['--pem-file', pem]
                    if arch == 'x86_64':
                        flags += ['--digest', 'sha1', '--digest', 'sha256']
                    run('rcodesign', '-C', '/dev/null', 'sign', *flags, thin)
                slices.append(thin)
            if len(slices) == 1:
                shutil.copy2(slices[0], binary)
            else:
                run(lipo, '-create', *slices, '-output', binary)
    elif command == 'safe-root':
        safe_root(*args)
    elif command == 'clean':
        clean(*args)
    elif command == 'validate':
        validate(args)
    else:
        parser = argparse.ArgumentParser()
        for name in ('platform', 'name', 'input', 'output', 'binary', 'plist', 'format', 'prefix',
                     'architecture', 'package-id', 'version', 'maintainer', 'description', 'compression', 'owner', 'lifecycle', 'lipo', 'ldid', 'main-path'):
            parser.add_argument('--' + name, default='')
        for name in ('resource', 'font', 'localization', 'map', 'embed', 'framework', 'install', 'launchd', 'script', 'exclude', 'package-file', 'arch', 'binary-check', 'extra'):
            parser.add_argument('--' + name, action='append', default=[])
        a = parser.parse_args(args)
        {'bundle': bundle, 'package': package, 'validate-one': validate_one}[command](a)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
