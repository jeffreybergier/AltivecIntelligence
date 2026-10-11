# altivec-app

Dependency-free Node >=22 CLI with offline, versioned project templates.
`altivec-app templates --json` exposes supported platforms, slices, compiler
floors, memory policy, packages and privilege requirements. No SDK or Git is
needed to generate; Python 3 validates plists. ImageMagick is optional, only
for replacing placeholder icons with custom artwork.

```sh
altivec-app new --template cocoa-shared --name Hello \
  --bundle-id com.example.hello --destination ./Hello --dry-run
altivec-app new --template cocoa-shared --name Hello \
  --bundle-id com.example.hello --destination ./Hello
cd Hello
make test-host
make check-project
make macOS-release
make macOS-analyze
make macOS-validate-package
```

Families: `ios-basic`, `mac-basic`, `cocoa-shared`, `cocoa-daemon`, `daemon`,
`cli-library`. Select a platform subset with `--platform macOS,iOS` or a Mac
architecture profile with `--mac-archs legacy|full|arm64|x86_64`. The iOS daemon
family supports rootful DEB; Cocoa plus daemon also supports rootless DEB
(`--ios-package deb-rootless` selects arm64). GUI-only iOS templates use a
sandboxed IPA. Services demonstrate a local PING/PONG protocol, not a general
purpose privileged execution interface. No credentials or app business logic
are copied from sibling projects.

All templates include portable model tests and an external static-library
consumer. Service templates also exercise readiness, request/response, clean
shutdown and restart with local Unix sockets. `SANITIZE=1 make test-host` adds
ASan/UBSan. Native scripts require explicit host, stage and platform settings;
no personal device aliases are generated. Select `NATIVE_MODE=ui` for Mac window launch/close/reopen and a screenshot,
or `NATIVE_MODE=installed` for guarded rootful iOS service installation, restart,
reinstallation and removal. The default executable mode never installs. iOS UI
rendering/sandbox behavior and rootless installed lifecycle remain separate checks.

Generation renders into a sibling temporary directory, validates metadata and
artwork, then exclusively reserves the destination. Existing directories,
files and symlinks are never overwritten. Make paths with whitespace are
rejected early. Templates record their schema/version; review upgrades by
regenerating elsewhere and diffing. There is no automatic code updater.

The canonical on-device starter is `templates/ios-device`; the device DEB
build copies this directory directly. The Node generator shares its UIKit
sources, plist profile and `template.conf` contract. The device shell generator
continues using `/var/altivec` native Make, independently of container compilers.
The phone portrait support profile deliberately does not claim tablet support.
Placeholder PNG/ICNS artwork is generated with Node built-ins, including Tiger
RGB/mask ICNS representations; no normal build runs artwork generation.

`templates/compose.yml` is a packaged copy of the repository template, with a
regression check preventing drift. `npm pack --offline --ignore-scripts` ships
all source templates and no npm dependencies. Tests run with
`node --test test/altivec-app.test.cjs` from the repository root. Run the generated
SDK matrix with `bash test/test_app_templates_container.sh` in the existing image
with the checkout mounted at `/altivec` and SDK volumes mounted read-only.

Template code and placeholder artwork are original MIT-licensed examples.
The existing MIT-licensed device starter is preserved. Build architecture is
informed by ENIL, Strappy-Cocoa, Retro-Cloud-Sync and Retro-DLP; none of their
application-specific code or artwork is redistributed here.
