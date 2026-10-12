"""Package already-built SQLite adapters without rebuilding the toolchain."""
import os
from pathlib import Path
import zipfile

module = Path(__file__).resolve().parents[1]
prebuilt = Path(os.environ['ALTIVEC_RELEASE_PREBUILT_ROOT']) / 'libs/cocoa-sqlite'
output = module / 'build-release'
output.mkdir(exist_ok=True)
for platform, suffix in [('mac', 'macOS'), ('phone', 'iOS')]:
    source = prebuilt / ('build-' + platform)
    archive = output / ('AltivecCocoaSQLite-' + suffix + '-static.zip')
    # Preflight all inputs before replacing an archive.
    library = source / 'lib/libAltivecCocoaSQLite.a'
    headers = sorted((source / 'include').rglob('*.h'))
    if not library.is_file() or not headers:
        raise SystemExit('Missing SQLite adapter build: ' + str(source))
    temporary = archive.with_suffix('.tmp')
    with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as package:
        package.write(library, 'lib/' + library.name)
        for header in headers:
            package.write(header, header.relative_to(source))
        package.write(module.parents[1] / 'LICENSE', 'LICENSE')
    temporary.replace(archive)
