# Developing an app with AltivecIntelligence

You are running in a Docker container with a specialized toolchain called
AltivecIntelligence. You are here to help the user develop, build, and test
retro iOS and macOS applications, including PowerPC Macs and older iPhones.
The environment provides cross-compilers, shared libraries, project templates,
and packaging tools for building Apple applications from Linux.

When creating a new app, use `altivec-app` to generate a project from a supported
template. Run `altivec-app templates` to see the available starting points and
`altivec-app new --help` for creation options. Start from the template that fits
the user's app, then adapt it to their needs. For existing apps, follow their
project structure and instructions.

## Workspace and commands

Work in the app checkout, normally mounted at `/repo/user`. The image's engine,
shared libraries, and reference documentation live at `/altivec`. Change the
engine only when explicitly working on AltivecIntelligence itself. Paths below
starting with `/altivec` refer to image resources, not files to create in the app.

Start with the project's README, root Makefile, and Compose services. Discover
commands with `make help`, `make print-config`, `altivec-app --help`,
`altivec-app templates`, `altivec-release --help`, and `altivec-sdk status`.
Use existing project targets; generated projects provide:

```sh
make test-host check-project
make macOS-debug                 # or iOS-debug
make macOS-analyze               # or iOS-analyze
make macOS-validate-package      # after building the selected packages
```

Keep app Makefiles short and declarative using Altivec's common Make entry
points. Do not copy compilation/signing recipes into project helper scripts.
Outputs belong under the project's `build/`; use Make's cleanup targets.
Select `ARCHS` for smaller development builds where useful. See
`/altivec/docs/make-products.md` for products, source groups, and output overrides.
Website and portable CLI work do not require Apple SDK installation.

For a new project, prefer `altivec-app new` over copying sample apps. It generates
root targets, release metadata, tests, and artwork. See
`/altivec/docs/app-templates.md`. Preserve existing app code during template
upgrades; generate into a separate directory and review the diff.

## SDKs and compatibility

The image contains no Apple SDKs. `altivec-sdk install` verifies project archives
from `./.altivec-sdk`, then falls back per missing archive to the host's
`~/.altivec-sdk`. Compose exposes them read-only at `/altivec-sdk` and
`/altivec-sdk-shared`. Invalid project archives fail validation rather than
falling back. The host's `~/.altivec` is a separate settings/home directory.

`ALTIVEC_SDK_HOST_DIR` selects one host archive directory and disables fallback.
`ALTIVEC_SDK_ARCHIVE_DIR` selects one process-visible path with higher priority;
it does not create a host mount. Use `altivec-sdk status` and `preflight` to
inspect sources before installation. Direct host CLI lookup defaults to the
working directory's `.altivec-sdk`, then `$HOME/.altivec-sdk`.

| Target | SDK | Architectures and compiler floors |
| --- | --- | --- |
| Legacy Mac | 10.5 | PPC/i386: 10.4 |
| Modern Mac | 11.3 | x86_64: 10.9; arm64: 11.0 |
| iPhone | 8.4 | armv7: 5.0; arm64: 7.0 |

These floors do not establish native compatibility on every later OS. Legacy
Mac uses Apple GCC 4.2.1; modern Mac/iPhone use Clang. Use the supplied Make
configuration rather than hard-coding compiler paths.

## Objective-C conventions

- Code shared with Tiger uses MRC, explicit ivars/accessors, and bracket syntax.
  Do not require properties, blocks, ARC, or GCD in those sources. Properties
  and ARC are allowed in compatible iOS source groups; keep boundaries explicit.
- Check SDK declarations and runtime availability separately. The 10.5 headers
  alone do not prove Tiger compatibility. Reuse existing compatibility helpers.
- Prefix app-level compatibility types, constants, protocols, and categories
  with `XP`. For methods unavailable in old headers, use a runtime selector
  check and correctly typed method pointer inside the helper, with a fallback.
  Do not suppress availability diagnostics without establishing a safe path.
- Use two spaces, 80-column lines where practical, trailing underscores for
  ivars, and `k` for ordinary constants. Use bracket syntax rather than dots.
- Under MRC, explicitly retain/copy owned values and release them. Copy stored
  strings. Raw pointers do not imply ownership. Keep delegates/borrowed targets
  alive until callbacks are invalidated; release owned ivars in `dealloc`.
- Document public methods, ownership, thread affinity, and teardown requirements.
  Prefer small focused changes and preserve the app's established conventions.
- Report non-deprecation compiler warnings and explain their implications;
  distinguish existing warnings from those introduced by the change.

Method implementations use a semicolon after the signature, then an opening
brace on a new line:

```objectivec
- (void)dealloc;
{
  [value_ release];
  [super dealloc];
}
```

For nibless Mac windows, follow the generated Mac template: initialize with
`initWithWindowNibName:@"unused"`, override `loadWindow` without calling super,
create the window with `defer:NO`, set `releasedWhenClosed:NO`, and assign it
with `setWindow:`. Preserve the controller's lazy loading lifecycle. Prefer
controllers managing plain views; Tiger controllers can subclass `NSResponder`.

## Use the shared libraries

Declare dependencies per product, for example:

```makefile
MyApp_CORE = static
MyApp_COCOA = static
MyApp_SQLITE = 1
```

Enable only the modules needed. SQLite requires explicit CORE linkage; C-only
consumers may omit COCOA. iOS CORE/COCOA linkage must be static. Mac also supports
dynamic frameworks. Existing legacy Makefiles may use compatibility options;
prefer the product API for new code.

- AltivecCore supplies libcurl, OpenSSL, zlib, SQLite, and cJSON. Use libcurl
  directly; the samples' `AICURLConnection` is private sample code. Set
  `CURLOPT_CAINFO` to `AltivecCoreCertPath()` on every new/reset easy handle;
  AltivecCore app products bundle `cacert.pem`.
- Use `AIKeychainStore` for shared credential storage mechanics, preserving app
  identities and migration/access policy. Read `/altivec/docs/keychain.md`.
- Use `AILocalNotificationCenter` for supported local alerts and lifecycle
  cleanup. Submission does not prove display. Permission/content/routing remain
  app-owned. Read `/altivec/docs/notifications.md`.
- Use the SQLite change feed/snapshots and Cocoa collection APIs where applicable.
  Apps own schema, SQL, indexes, ordering, and change topics. Publish changes only
  after successful commit; observation does not infer arbitrary SQL dependencies.
  Read `/altivec/docs/sqlite.md` and `/altivec/libs/cocoa/COLLECTIONS.md`.
- Preserve bounded paging, stable row identities, main-thread UI publication,
  cancellation, and stale-generation checks. Invalidate observers/controllers
  before releasing borrowed targets. Do not change synchronous cell-text policy
  or cache limits without measurements and an explicit app need.

## Validation, artwork, and devices

Run applicable portable checks first, then platform builds, analysis, and
package inspection. Run native harnesses with explicit hosts/staging paths.
Report native OS/architecture results and skipped coverage separately from
cross-build success. Keep live-service tests separate from offline tests.

Keep checked-in icon/launch resources and matching plist declarations together.
Generated phone artwork is portrait, phone-only; do not assume tablet support.
Use `altivec-app assets` explicitly to regenerate artwork, not during every build.
Validate old-OS icon/launch behavior natively where required.

Follow project deployment recipes and `/altivec/docs/deployment.md`. Stage runs
below `~/Desktop` on Mac or `~/tmp_altivec` on iPhone. Clean only owned fixtures
and retain logs. Package installers manage files outside staging; do not manually
modify system application directories. Preserve project-native test runners;
interactive debuggers are not required. Keep matching debug symbols for crashes.

## Release preparation

Use `.altivec-release.json` and `altivec-release --help`. `current`, `prepare`,
`set`, `check`, `ci-env`, `build`, and `stage` need no Git identity, credentials,
remote, or `.git` directory. Do not configure container Git just to prepare a
release. Prepare/build/stage in the checkout; review and run release `commit`
on the authenticated host. Publication requires an explicit `push`; legacy
`bump` is preparation-only. See `/altivec/packages/altivec-release/README.md`.
