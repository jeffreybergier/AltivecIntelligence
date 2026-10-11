# Generated projects

`altivec-app` is a dependency-free Node CLI packaged with offline templates.
The source checkout entry point is `bin/altivec-app`. The image installs the
exact local npm package; it does not fetch a helper at invocation time.

```sh
altivec-app templates --json
altivec-app new --template cocoa-shared --name MyApp \
  --bundle-id com.example.myapp --destination ./MyApp --dry-run
altivec-app new --template cocoa-shared --name MyApp \
  --bundle-id com.example.myapp --destination ./MyApp
cd MyApp
make test-host
make check-project
make macOS-release
make macOS-analyze
make macOS-validate-package
```

| Family | Products | Packages |
| --- | --- | --- |
| `ios-basic` | ARC UIKit UI, MRC facade, C model | Sandboxed IPA |
| `mac-basic` | MRC nibless AppKit UI, C model | Mac ZIP |
| `cocoa-shared` | Both UIs sharing a C model and narrow Objective-C facade | ZIP, IPA |
| `cocoa-daemon` | UI, service, IPC client; separately declared entitlements | Mac ZIP, rootful or rootless iOS DEB |
| `daemon` | Service and IPC client, no GUI | Mac ZIP, rootful iOS DEB |
| `cli-library` | Public C library and CLI consumer | Mac/iOS/Linux ZIPs, public header and license |

Use `--platform` to select a supported subset, `--mac-archs` for
`full|legacy|arm64|x86_64`, and `--ios-package` for an advertised format.
Rootless service packages select arm64 and `iphoneos-arm64`; rootful packages
use armv7/arm64 and `iphoneos-arm`. Service UIs are explicitly unsandboxed and
services run as a user/mobile; installing a jailbreak package requires root.
GUI-only iOS templates retain their application container. A package format
never silently changes sandbox policy.

Templates record their schema/version in `.altivec-template.json`. Generation
validates names, options, placeholders, plists and artwork before finalizing,
and refuses existing destinations, including symlinks. To review an upgrade,
generate into a fresh directory and diff; application code is never overwritten.
The initial supported iOS artwork profile is portrait phone. Tablet, networking
and SQLite demonstration profiles can be added later without cloning whole apps.

Generated Makefiles declare products using the shared build modules. `VERSION`
is the release source and `.altivec-release.json` uses actual root build paths.
Compose discovers SDK archives from the project and shared host folders. The
canonical device template is `packages/altivec-app/templates/ios-device`;
`toolchain/iOS/armv7/Makefile` packages that source directly. The old shell
initializer reads `template.conf` and retains the native `/var/altivec` backend.
No Node runtime is required on the phone.

## Test layers

1. `make test-host`: C boundary tests, public-library consumer, and applicable
   local IPC readiness/shutdown/restart. `SANITIZE=1` adds ASan/UBSan. No network
   service or remote machine is involved.
2. `make check-project`: source plist declarations, identifiers, localizations,
   PNG dimensions/checksums, and legacy ICNS structure/size limits.
3. Cross-build `debug release`, run `analyze` and `validate-package` for each
   configuration. Shared validation inspects slices, every declared executable's
   entitlements, plist metadata, DEB ownership and lifecycle paths/scripts.
   `python3 tools/check-artifacts.py` additionally checks deployment floors,
   dynamic dependencies, packaged resources and library symbols/consumer usage.
4. Explicit native tests use `NATIVE_HOST`, `NATIVE_STAGE`, `NATIVE_PLATFORM`.
   The default mode checks executable IPC/restart, `NATIVE_MODE=ui` checks Mac
   window lifecycle and saves a screenshot, and `NATIVE_MODE=installed` tests
   rootful iOS service installation/reinstallation/removal with pre-existing
   package/path guards. Inspect screenshots; successful command exit alone
   does not establish visual correctness. iOS UI/sandbox and rootless installed
   lifecycle checks remain device-specific. Staging stays below `~/Desktop`
   on Mac or `~/tmp_altivec` on iPhone. Logs are under `build/tests/native`.

CI separates dependency-free Node/Linux tests from the opt-in SDK matrix on
an explicitly provisioned `altivec-sdk` runner. That runner needs the existing
`altivec-intelligence:local` image and `altivec-ci-sdk-{legacy,modern}` volumes.
`test/test_app_templates_container.sh` generates each family and a rootless
variant, then tests/builds/analyzes/inspects them with networking disabled.
It does not rebuild the image or advertise native-device results.

Custom icon conversion invokes an existing ImageMagick `magick` executable;
placeholder artwork uses Node built-ins. `altivec-app doctor` reports capability
availability and SDK status without installing anything. Ordinary builds never
regenerate resources. Legacy ICNS elements stay within 300,000 bytes each and
1,000,000 bytes total; runtime icon/launch verification remains OS-specific.

## Local validation evidence

The development checks use the existing image with the checkout and installed
SDK volumes mounted in; the full container has not been rebuilt. Native evidence
is recorded separately: the generated AppKit window and icon were inspected on
PowerPC Tiger, including close/reopen; service IPC and restart ran on that Mac
and an armv7 iPhone. Rootful service installation, launchd restart, reinstall,
removal and preservation of test data passed on the iPhone. The shared
shell-generated starter compiled, packaged and
analyzed with the native iPhone toolchain. These observations do not establish
iOS 5 rendering, rootless installation, or all advertised compiler slices at
runtime. Preserve those distinctions in release notes.
