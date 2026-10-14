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
white placeholders use Node built-ins and bundled JPEG 2000 images. Ordinary
builds never regenerate resources. Legacy ICNS elements stay within 300,000 bytes each and
1,000,000 bytes total; runtime icon/launch verification remains OS-specific.

## Placeholder artwork contract

All generated icons and launch screens are opaque white. The native-device
starter and checked-in SingleScreen/CURLphone fixtures share the same phone-only,
portrait launch profile:

| Display points | PNG pixels | Filename |
| --- | --- | --- |
| 320 × 480 | 320 × 480 / 640 × 960 | `Default.png` / `Default@2x.png` |
| 320 × 568 | 640 × 1136 | `Default-568h@2x.png` |
| 375 × 667 | 750 × 1334 | `Default-iOS8-667h@2x.png` |
| 414 × 736 | 1242 × 2208 | `Default-iOS8-736h@3x.png` |
| 375 × 812 | 1125 × 2436 | `Default-iOS11-812h@3x.png` |
| 414 × 896 | 828 × 1792 / 1242 × 2688 | `Default-iOS12-896h@2x.png` / `@3x.png` |

Keep `UILaunchImageFile=Default`, `UIDeviceFamily=[1]`, portrait orientation,
and the matching `UILaunchImages` declarations. The plist sizes are in points,
not pixels; the image names omit scale modifiers. See Apple's
[launch-image size](https://developer.apple.com/documentation/bundleresources/information-property-list/uilaunchimages/uilaunchimagesize)
and [filename rules](https://developer.apple.com/documentation/bundleresources/information-property-list/uilaunchimages/uilaunchimagename).
The 568h filename preserves the legacy tall-screen opt-in. These static images
cover the listed profile; they do not promise native sizing on every newer iPhone
or iPad. Verify screen bounds and rendering on each target OS/device.

Mac `AppIcon.icns` matches the formats and sizes in ENIL's icon, with original
white pixels: 16/32/48/128px planar RGB with separate 8-bit masks (`is32/s8mk`,
`il32/l8mk`, `ih32/h8mk`, `it32/t8mk`), plus 256/512/1024px JPEG 2000
(`ic08`, `ic09`, `ic10`). High-resolution images are bundled so offline generation
needs no image converter. Custom artwork requires ImageMagick with JPEG 2000
support and must still fit the legacy element/file size limits.

## Final-image integration

The Containerfile runs `test/final-image-smoke.sh` after installing the exact
local npm packages, with networking disabled. It generates all six families,
runs their host tests and metadata/artwork checks, parses the final Make modules,
and checks release versions. Use `altivec-app templates` for template discovery,
`altivec-release doctor` for release diagnostics, and `altivec-sdk status` for
SDK status without installing SDKs.

The accompanying `website-smoke.sh` uses Ruby ERB and Bundler, serves generated
HTML with Python, and checks it in Chromium. It does not fetch gems or require
Apple SDKs. Jekyll/plugins remain website-owned Gemfile dependencies; this is
an image-tooling check, not a build of a particular Jekyll website.

Run `bash /altivec/test/final-image-smoke.sh` inside an image to repeat it.
The SDK-dependent generated-project matrix remains a separate check.

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
