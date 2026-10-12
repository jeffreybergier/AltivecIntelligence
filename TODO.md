# AltivecIntelligence improvement plan

Repository review: 2026-10-10. Unchecked items are proposed work; checked items
record implemented behavior. The evidence table records the review baseline.

The highest-value change is to turn the working patterns in the newer projects
into supported build, packaging, and template primitives. Keep Make responsible
for compilation and Node responsible for discoverable developer commands. Make
local development useful without Git configuration, credentials, or a device.

## Evidence from the current projects

Sibling paths below refer to the accompanying checkouts in `Vibing/`.

| Source | Existing pattern worth adopting |
| --- | --- |
| `bin/altivec-release` | Version checking, named build targets, multiple artifacts, and CI staging are useful. `bump` couples version edits to commit/tag/push; `--no-push` still needs a Git checkout and commit identity. Basic argparse help exists, but lacks a guided host/container workflow. |
| `bin/altivec-chooser`, `Containerfile` | A dependency-free Node executable already fits the image. Chooser is currently a checked-in script, not a standalone npm package; use that runtime model and add npm packaging where useful. |
| `altivec_common_{app,mac,phone}.mk` | Existing source groups, resource/localization helpers, entitlements, optional AltivecCore/AltivecCocoa, and analysis should be extended rather than discarded. Public debug/release/clean recipes still assume source-local build directories. |
| `../ENIL/source/make/{paths,native-targets}.mk` | Root-level `build/<platform>/<configuration>`, child-target forwarding, guarded cleanup, and help. ENIL bypasses shared release/debug recipes and replaces IPA packaging to make absolute output paths work. Its root Makefile also exposes host tests and Worker npm scripts. |
| `../Strappy-Cocoa/source/{iOS,macOS}/Makefile` | UI plus daemon, portable C and Objective-C boundaries, ARC iOS UI with MRC shared code, separate daemon entitlements, and rootful/rootless Debian packaging. Outputs still use nested build-release directories. |
| `../Retro-Cloud-Sync/source/make/` | App/daemon/library composition, bundled Mac helper, root-level outputs, rootful iOS lifecycle packaging, portable business tests, and remote native integration/UI tests. |
| `../Retro-DLP/make/`, `../Retro-DLP/source/gui/` | CLI plus public static libraries plus Cocoa apps; Linux tests and sanitizers; consumer/package validation; selectable legacy Mac architectures; sandbox-preserving iOS entitlements; explicit artwork and package checks. Its apps also work around shared output/IPA assumptions. |
| `toolchain/iOS/common/helpers/altivec-app.sh` and `toolchain/iOS/armv7/payload/share/altivec/` | Existing safe destination checks, a complete sandboxed iOS starter, shared C model, localization, icons/launch images, and native-device Make backend. Preserve this capability. |
| `../jeffreybergier.github.io/compose.yml` | The same image supports Ruby/Bundler/Jekyll serving. Apple SDK setup must remain unnecessary for website work. |

## 1. Replace release orchestration with an obvious local-first Node CLI

### Behavior and discovery

- [x] Implement a dependency-free Node CLI, packaged for installation through npm
  on a host as well as inclusion in the image. Pin the packaged version in the
  image; do not download the latest release helper on every invocation.
- [x] Make no arguments print useful usage and examples. Support top-level and
  per-command `--help`, `--version`, `--dry-run`, and machine-readable output for
  inspection commands. Help must work outside a project, without SDKs or Git.
- [x] Separate file preparation, local Git operations, and publication. Suggested
  interface:

  ```sh
  altivec-release doctor
  altivec-release current
  altivec-release prepare patch --dry-run
  altivec-release prepare patch
  altivec-release build --target iOS
  altivec-release stage
  # On the host checkout, after reviewing the prepared changes:
  altivec-release commit
  # Only when the user explicitly requests publication:
  altivec-release push
  ```

  `prepare` updates version files and writes a reviewable plan under
  `build/release/`; it does not require `.git`, identity, remote access, or keys.
  `commit` verifies that plan and commits only its version files, then creates the
  local tag. `push` is an explicit, separate operation. Retain `set`, `check`,
  `ci-env`, `build`, and `stage` semantics where workflows already depend on them.
- [x] Define what happens to old `bump` invocations: migrate documentation and
  callers, then make it a clearly documented local preparation alias or an
  actionable migration error. Never preserve implicit pushing as a surprise.
- [x] `doctor` should distinguish missing checkout, missing identity, detached
  HEAD, unrelated dirty files, absent remote, and credentials not checked.
  Ordinary inspection/preparation must not probe the network. An explicit remote
  check should distinguish authentication/network failure from an absent tag.
- [x] Print exact next steps for the current environment. Prefer preparing on the
  mounted checkout inside Docker and committing/pushing from the authenticated
  host. Offer optional SSH-agent forwarding or runtime token injection as
  documented alternatives, without baking secrets into images or copying a
  private key directory. Tokens do not configure Git author identity or SSH.
- [x] Read the user's existing Git identity; accept explicit per-invocation
  identity when needed, without changing global configuration. Recheck version
  files, branch, tag availability, and unrelated staged changes before commit.
  Handle partial commit/tag/push failures with resumable steps, not a second bump.

### Configuration without npm dependencies

- [x] Prefer a versioned `.altivec-release.json` schema, parsed with Node built-ins.
  Do not implement a partial YAML parser. Provide a one-time YAML-to-JSON
  converter using the existing Python/PyYAML environment during migration; the
  installed new CLI should need no npm libraries or PyYAML for normal operation.
- [x] Address plist handling explicitly: Node has no built-in plist parser.
  Prefer generating version metadata from one plain version source and checked-in
  plist templates for new projects. For existing XML plists, implement and test
  a narrowly defined updater that validates every requested key and rejects
  unsupported formats before writing anything. Do not silently damage binary
  plists or introduce a hidden runtime dependency.
- [x] Preserve named targets, custom workdirs, per-plist key lists, multiple
  artifacts, and asset-name substitutions. All four app repositories use these;
  Retro-DLP needs CLI, app, and library assets, while Strappy needs two DEBs.
- [x] Preflight all version edits before applying any; use temporary files and
  recoverable writes. Validate destination paths and duplicate asset names before
  staging. Produce an artifact manifest with version, target, checksum, and
  provenance when available; a source archive must still work without Git.
- [x] Support a non-plist version source for CLI/library and website projects.
  Keep build actions generic. Prefer executable-plus-argument arrays for new
  configuration, with explicitly marked shell actions for existing pipelines.
- [x] Migrate CI together with configuration. Existing workflows call `ci-env`,
  `build`, and `stage`, validate `dist/*`, then use `gh release upload`. Retain
  `dist` compatibility or an explicit staging override while moving new defaults
  to `build/release`; do not silently break release globs.

**Done when:** preparation succeeds in an exported source tree and an
unauthenticated container; host commit/tag and explicit push are independently
usable; help explains both workflows; existing release configurations have
migration fixtures; mocked failures leave recoverable state and never push
implicitly. Include malformed versions/plists, unrelated staged files, duplicate
assets, detached HEAD, existing tags, and failed remote checks in CLI tests.

Implemented as `packages/altivec-release` version 1.0.0, with the source-tree
entry point in `bin/altivec-release`. The image installs the exact local npm
package offline. Repository configuration/templates and CI staging calls have
migrated; sibling YAML configurations are covered by migration fixtures and can
be converted with `altivec-release migrate` without changing those repositories
here. Validation: 41 Node tests, workflow/template lint, real-config dry-run,
and installed-package smoke in the local image with Git absent from PATH. The
full SDK/toolchain image was not rebuilt for this CLI change.

## 2. Retire altivec-deploy

- [x] Remove `bin/altivec-deploy`, its dedicated test, `docs/altivec-deploy.md`, and
  debugger-init templates after auditing references in README, AGENTS, image
  checks, and examples. A temporary message-only compatibility stub is optional
  if existing users need a transition release.
- [x] Replace the large deployment abstraction with short, editable recipes:
  transfer and launch a Mac bundle; install an IPA; install rootful/rootless DEBs;
  retrieve logs/crash reports; start and stop a test daemon. State prerequisites,
  package type, writable staging location, and cleanup ownership.
- [x] Keep SSH/SCP/rsync and symbol generation. Audit `lldb` and other debugger-only
  image dependencies for removal; keep LLVM components needed by builds,
  analysis, and `dsymutil`. Debuggers can be documented as optional tools.
- [x] Preserve project-specific native test runners. Removing deployment tooling
  should not remove automated device tests or force interactive debugging.

**Done when:** no template or agent guide recommends altivec-deploy; sample
artifacts still have documented manual install/run/log instructions; normal
builds and tests never require a debugger.

Implemented with `docs/deployment.md` recipes and updated README, FAQ, and
agent guidance. Removed the command, its dedicated tests, debugger-init templates,
and the explicit image `lldb` dependency. Build/symbol tools and native test
runners are retained. Validation: 8 offline build/package tests and 41 release
CLI tests passed in the existing Linux image; recipe shell syntax, documentation
links, and whitespace checks passed. The macOS host run had one failure in an
unchanged architecture-validation test (which passed in Linux). The full image
was not rebuilt; real-device recipes still require hardware validation.

## 3. Make repo-root builds and composed products first-class

### One output convention

- [x] Introduce explicit `PROJECT_ROOT` and `BUILD_ROOT`, resolved from the
  project's root Makefile or a generated project marker, not the shell's current
  directory or `git rev-parse`. Export the resolved absolute root to child makes.
  Use ENIL's implementation and build-system tests as the starting point.
- [x] Default to this structure (a simple app can omit the product level):

  ```text
  build/
    macOS/release/<product>/        # bundle/archive, symbols, Intermediates/
    macOS/debug/<product>/
    iOS/release/<product>/
    linux/debug/<product>/
    analyze/<platform>/<product>/
    tests/<platform>/<suite>/
    release/                       # staged assets and release manifest
  ```

- [x] Fix public `release`, `debug`, `clean`, and `analyze` recipes to honor the
  selected root. Fix the phone IPA recipe's `../../$@` assumption with an absolute
  archive destination and isolated staging. ENIL and Retro-DLP should no longer
  need their private IPA workarounds.
- [x] Keep build roots collision-free across products, configurations, platform,
  architectures, SDKs, and flags. Preserve relative source paths in object names
  so two `main.c` files do not collide. Track headers and resource changes;
  isolate ARC/MRC and generated-source inputs.
- [x] Support safe clean scopes: current product/platform and explicit whole-root
  cleanup. Reject empty/root/source paths and dangerous symlink resolutions.
  Normalize relative overrides against PROJECT_ROOT. Either support whitespace
  consistently or reject it early with a precise explanation.
- [x] Update release manifests, CI globs, `.gitignore`, sample docs, analyzer paths,
  and device scripts together. Migrate app outputs before touching prebuilt
  `/altivec/libs/*/build-{mac,phone}` locations, which are an existing consumer
  contract. Eventually consolidate image-build intermediates separately.

Implemented in the shared root/entry modules and product graph, with sibling
consumer migrations for ENIL, Retro-DLP, Retro-Cloud-Sync, and Strappy-Cocoa.
Static library directories use a `lib` prefix to avoid case-insensitive collisions
such as RetroDLP/retrodlp. Explicit `BUILD_VARIANT` directories retain concurrent
SDK/flag variants; shared host/container locks serialize writes to the same
output and exclude cleanup. Product/platform cleanup and `clean-all` are separate.
Prebuilt library locations and image-build intermediates remain unchanged.

Validation includes offline dependency/root/cleanup/analyzer tests, real SDK
product/signing/package matrices, all four app build and offline suites, release
staging and 41 release CLI tests. Device coverage on x4-vm and koolphone5 includes
Retro-DLP UI, Retro-Cloud-Sync UI/service behavior, and Strappy schema/auth probes.
No image rebuild was needed; validation mounted the changed modules into the
existing image. Run `make clean` once when upgrading an old flat output tree.

### Small reusable Make modules

Small application Makefiles are the critical measure of success. Each project
should declare its sources, products, dependencies, resources, and build options
in a short, readable Makefile; shared Altivec modules should own the build
mechanics. Moving complexity into project-local helper Makefiles or scripts
does not satisfy this goal.

- [x] Split compilation, universal merging, resources, signing, and packaging
  into reusable fragments behind the existing common-Makefile entry points.
  Offer products for app, command-line executable, static library, and daemon,
  with explicit dependencies between them.
- [x] Make architecture sets configurable. Support the full existing Mac and
  iOS matrices, legacy-only PPC/i386 (Retro-DLP), and single-slice development
  builds without overriding internal link rules. Declare SDK/deployment floors
  per slice and validate library slices before linking.
- [x] Provide documented source groups and per-language/per-group flags for C,
  C++, Objective-C, and Objective-C++. Preserve Tiger MRC and optional ARC only
  in compatible iOS UI groups. Do not force one app's memory model on every app.
- [x] Promote current ad hoc hooks into named inputs: extra static libraries,
  generated files, nested resource bundles, fonts/licenses, localizations,
  embedded executables, helper plists, entitlements, and package scripts. Keep
  an escape hatch, but make normal dependencies visible to Make.
- [x] Provide packaging modules for Mac ZIP, sandboxed iOS IPA, and jailbreak
  rootful/rootless DEBs. Model install prefix, package architecture, ownership,
  compression, launchd definitions, and lifecycle hooks explicitly. Strappy's
  `Architecture: all` policy and rCloud's `iphoneos-arm` policy are project
  choices to validate, not a universal default to copy.
- [x] Treat sandbox policy and package format as separate choices. A rootless
  install does not imply an unsandboxed application; Retro-DLP explicitly keeps
  its app container. Sign each executable with its own entitlements and test
  the resulting package, including embedded daemons/helpers.
- [x] Add `make help`, `print-config`, `test-host`, `test-native`, and
  `validate-package` conventions. Show resolved outputs, compiler/SDK selection,
  architectures, minimum OS, and required inputs without building everything.

**Done when:** simple app, app-plus-daemon, and CLI/library/app fixtures each use
small, declarative application Makefiles without copied compile/link/sign/package
recipes or overrides of internal engine rules; root and child invocations agree;
`make -j debug release` does not
mix outputs; changing headers/resources triggers the right rebuild; absolute and
relative BUILD_ROOT overrides work; clean cannot erase source; simple app,
app-plus-daemon, and CLI/library/app fixtures all package under root `build/`.

## 4. Bring altivec-app into the container with useful templates

### Generator and shared template source

- [x] Add a dependency-free Node CLI with npm packaging. Include templates in the
  installed package/image so generation works offline. Proposed interface:

  ```sh
  altivec-app templates
  altivec-app new --template cocoa-shared --name MyApp \
    --bundle-id com.example.myapp --destination ./MyApp
  altivec-app new --help
  altivec-app doctor
  ```

- [x] Publish template descriptions and their supported platform, architecture,
  minimum OS, memory model, package, and privilege combinations. Reject invalid
  combinations before creating files. Support noninteractive flags and a dry-run
  file list; optional prompts should not be required by agents.
- [x] Preserve existing no-overwrite and path validation behavior. Render into a
  temporary directory, validate placeholders/metadata, then finalize. Generate
  project-specific README, AGENTS, root Makefile, ignore rules, release config,
  Compose setup, and test entry points with working examples.
- [x] Share template assets and a small declarative template manifest between
  container and device tooling. Keep a shell-compatible on-device generator for
  old iPhones unless a supported Node runtime is actually demonstrated there.
  Share a project contract, not hard-coded compiler paths: container cross-build
  and `/var/altivec` native-device backends remain distinct.
- [x] Record template/schema version in generated metadata. Later upgrades should
  produce a reviewable diff; never overwrite application code automatically.

### Initial template families

| Template | Scope and inspiration |
| --- | --- |
| `ios-basic` | Existing altivec-app starter: sandboxed, programmatic UIKit, shared C model, icons, launch images, localization, IPA. |
| `mac-basic` | Updated SingleWindow with tested nibless window lifecycle, MRC, selectable legacy/full architecture matrix, ICNS and ZIP. |
| `cocoa-shared` | ENIL/Retro-DLP structure: portable C model, a narrow Objective-C facade, AppKit/UIKit frontends, compatibility helpers, host tests. Optional SQLite/libcurl teaching components remain a future extension. |
| `cocoa-daemon` | Strappy/rCloud structure: UI plus helper, explicit IPC boundary, separate entitlements, launchd/lifecycle files, rootful/rootless options where supported. |
| `daemon` | Headless service plus tiny test client; no mandatory GUI. Rootful iOS packaging and Mac launchd variants, with privilege and installation instructions. |
| `cli-library` | Retro-DLP structure: portable public C API, CLI consumer, Linux harness/sanitizers, Apple cross-builds, headers/library/license packaging. |

- [x] Start with basic Mac/iOS and shared-core templates; add daemon/CLI families
  after the build modules stabilize. Compose shared-core, localization and
  daemon source components rather than copying every combination into a
  separate full app. Extract minimal examples, not the applications' business
  logic, credentials, protocol integrations, or large dependency trees.
- [x] Generate explicit compatibility boundaries like XPAppKit/XPUIKit and
  XPFoundation, with a small tested example. Audit extracted code and licenses.
  Keep app-specific compatibility policy out of universal template assumptions.

### Artwork and packaging that survive old devices

- [x] Ship valid placeholder artwork and an explicit asset-generation command.
  Generate legacy iOS icon sizes, matching plist declarations, launch images
  for the selected phone profile, and legacy ICNS representations.
  Reuse the device starter and Retro-DLP checks instead of assuming modern asset
  catalogs or storyboard compilation are available in Linux.
- [x] Keep generated artwork as ordinary project resources; normal builds should
  not regenerate it. Validate declared files, image dimensions, ICNS element
  structure, localization encoding, and bundle identifiers.
- [x] Carry forward Retro-DLP's documented Leopard limits (300,000 bytes per ICNS
  element and 1,000,000 bytes total) as a tested compatibility profile. Record
  native icon/launch evidence separately from structural validation.
- [ ] Extend native icon/launch evidence to iOS 5 and Leopard; those OS versions
  were not available on the supplied test machines.
- [x] Distinguish zero npm dependencies from zero external tools: asset conversion
  can invoke a documented image tool already provided by the environment.
  `doctor` should report missing converters, signing tools, and SDKs by feature.

**Done when:** each supported template can be generated offline, built, analyzed,
packaged, and host-tested without hand-editing paths; its native backend is tested
on a supported device where claimed; a second generation never overwrites files.

Implemented as `packages/altivec-app` 1.0.0, with `bin/altivec-app` for the
source checkout and a pinned offline install in the image recipe. All six
families compose small reusable source components and declarative Make products.
The canonical `templates/ios-device` tree and version manifest are shared with
the device shell generator; its `/var/altivec` backend remains separate.
See `docs/app-templates.md` for supported combinations and test commands.

The initial artwork profile is phone-only portrait. Tablet support and optional
networking/SQLite teaching components are future extensions, not advertised
options. Mac icon rendering and window lifecycle were checked on PowerPC Tiger;
iOS 5 rendering and Leopard-specific runtime behavior were not tested. The
image recipe and installed npm package were checked without rebuilding the full
SDK/toolchain image; the running image needs a checkout mount or the next rebuild
to expose the new generator.

## 5. Add project-first SDK archive discovery with a shared host fallback

Implemented in `73c59f2` (`feat(sdk): add project-first shared archive discovery`).
`bin/altivec-sdk` resolves each archive from the project first, then the shared
host folder. `docker/build-sdk-dependent.sh` uses the same lookup through
`altivec-sdk locate`.

- [x] Add per-archive lookup with this default host search order: the project's
  `./.altivec-sdk/` first, then `~/.altivec-sdk/`, shared across projects. Use the
  shared copy when an archive is absent locally, including when the project
  folder is missing or contains only some of the required archives. The host's
  `~/.altivec/` is currently mounted as the container's `/root` for settings and
  credentials; the separate shared archive directory is `~/.altivec-sdk/`.
- [x] Preserve explicit `ALTIVEC_SDK_HOST_DIR` and `ALTIVEC_SDK_ARCHIVE_DIR`
  overrides and document how they take precedence over default discovery. Keep
  `status`, `preflight`, and `install` consistent, report the selected archive
  paths, and retain existing archive validation. Report an invalid project copy
  rather than silently substituting a shared copy.
- [x] Update `compose.yml`, `templates/compose.yml`, and the image-build SDK
  inputs to expose the required host directories read-only and support the same
  precedence. Container home paths do not automatically refer to the host's
  home directory; account for the SDK-only service and BuildKit contexts too.
- [x] Update README/AGENTS guidance, CLI help, and Compose examples with the
  search order, host-to-container paths, overrides, and shared-folder setup.
  Add coverage for project precedence, shared fallback, split archive sets,
  missing directories, explicit overrides, and invalid archives.

Compose mounts the project and shared folders read-only at `/altivec-sdk` and
`/altivec-sdk-shared`, including the SDK-only service; BuildKit uses two matching
archive contexts. `ALTIVEC_SDK_HOST_DIR` selects one host folder and disables
fallback. `ALTIVEC_SDK_ARCHIVE_DIR` takes precedence and selects one path visible
to the process; it does not create a host mount. Local image builds require both
context directories to exist, or one existing folder selected by the host
override.

Validation on 2026-10-12: the SDK discovery suite passed 8 tests, including
Compose source mappings, project precedence, shared fallback, split archive
sets, overrides, and invalid archives. Two tests were skipped: installation
requires Linux's `flock`, and the BuildKit smoke test is opt-in. This check did
not rebuild the image or rerun those two tests.

## 6. Make validation useful to agents and humans

- [x] Provide layered test recipes: portable C/Linux tests first, cross-build and
  artifact checks next, native integration and UI smoke tests explicitly selected.
  Successful Linux tests or cross-compilation must not be reported as device
  launch, rendering, sandbox, or daemon-lifecycle validation.
- [x] Borrow offline harness patterns from Strappy, ENIL's loopback tests, rCloud's
  portable/native separation, and Retro-DLP's external consumer and sanitizer
  checks. Keep live-service tests opt-in and separate from default tests.
- [x] Use small project-owned SSH test scripts with explicit host and staging
  directory settings, timeouts, exit status, and log collection. Do not recreate
  altivec-deploy as a mandatory remote orchestration framework. Do not bake local
  host aliases or personal devices into generated templates.
- [x] Add package inspection for slices/deployment targets, dynamic dependencies,
  symbols, plists, entitlements, resource/license presence, archive layout, and
  DEB metadata/lifecycle paths. Native tests should cover launch, IPC readiness,
  restart, upgrade, uninstall, and preservation of user data where applicable.
- [x] Test the generator/release CLIs with Node's built-in test runner. Add a small
  generated-project matrix in CI, with SDK-dependent jobs clearly separated from
  dependency-free CLI and Linux harness tests. Reuse existing on-device
  `ios-app-make-check.sh` and `device-ios-app-smoke-test.sh` where appropriate.

Implemented with generated portable/sanitizer/consumer tests, project and
archive inspection, explicit SSH executable/Mac UI/rootful installation recipes,
and separate portable/opt-in SDK CI jobs. The SDK matrix generates all six
families plus a rootless variant; debug/release builds, analysis, package
validation and archive inspection passed in the existing network-disabled image.
The Node generator/release suites passed 57 tests, including standalone offline
npm installation and generation. Existing device generator/Make contract checks
also passed against the canonical template.

Native evidence: x4-vm (PowerPC Tiger) passed generated Mac UI launch/close/reopen,
with screenshot inspection, and service IPC/restart. koolphone5 passed service
IPC/restart and guarded rootful install, launchd restart, reinstall, removal and
preservation of test data. The shared shell-generated iOS starter built, packaged
and analyzed using its native compiler. iOS UI/sandbox behavior and rootless
installed lifecycle are not inferred from these results. No personal host aliases
are embedded in generated projects.

Matrix testing also fixed native Linux analyzer/package validation defaults and
two parallel-build races: output ownership publication and a mutex released
between acquisition failure and inspection. Regression coverage lives in the
shared Make contract suite (17 passing tests).

## 7. Image and documentation follow-through

- [ ] Add a lightweight `altivec doctor`/tool index, or consistent per-tool doctor
  commands, for image version, build capabilities, SDK status, and template
  locations. Use the existing SDK catalog and installer rather than introducing
  another SDK manager. Website and CLI-only work should not trigger SDK installs.
- [ ] Keep the current Jekyll/Ruby, Node, Python, and browser tooling usable while
  removing obsolete deployment machinery. Add a small website smoke check so
  Apple-focused refactors do not break the shared development image.
- [ ] Bundle installed CLI code, templates, and Make fragments from the same
  release. Check package contents and executable entry points in image smoke
  tests. Share tiny helpers only when multiple tools actually need them.
- [ ] Rewrite README/AGENTS examples around generated projects and root commands.
  Reconcile documented deployment floors with actual compiler flags and device
  evidence: sibling guides mention iOS 4.3 while the container/device template
  guidance describes iOS 5.0. Do not advertise a broader tested matrix by inference.
- [ ] Keep tiny sample apps as build fixtures; make richer examples generated
  from supported templates so documentation and templates cannot drift apart.
  Replace duplicated CURL-wrapper teaching examples with a minimal direct-libcurl
  or shared-model example matching the current development guidance.

## 8. Extract shared application capabilities into AltivecCocoa

Capability review: 2026-10-12. These are new proposals, not implemented APIs.
The goal is smaller app facades and controllers: apps supply domain queries,
row presentation, notification content, and job policy; Altivec owns reusable
lifecycle, threading, compatibility, and delivery mechanics. Not every app
needs every module. Names below are provisional.

### Evidence and first consumers

Paths are relative to the sibling repositories named in the first column.

| Consumer | Reviewed implementation | Extraction opportunity |
| --- | --- | --- |
| ENIL | `source/{iOS,macOS}/XP{UIKit,AppKit}.{h,m}`, `source/iOS/AppDelegate.m` | `XPUserNotificationCenter` wrappers, badges, permission handling, foreground cleanup, and background assertions. |
| Retro-DLP | `source/gui/iOS/RDLPAppDelegate.m`, `source/gui/iOS/RDLPUIKit.m` | Download-completion notifications and finite background work with expiration, cancellation, and operation counting. |
| Strappy-Cocoa | `source/shared/strappy_store_client.{c,h}`, `source/shared/StrappySession.m`, `source/daemon/tests/store_changes_harness.c` | Worker refresh hints, scoped revision journals, independent consumer cursors, overflow/reconnect resync, and Objective-C publication. |
| Retro-DLP | `source/gui/shared/rdapp_store.{c,h}`, `source/gui/shared/RDLPLibrary.{h,m}` | Count/page/seek queries, immutable WAL-backed row collections, bounded row caching, stable identities, and C-to-main-thread callbacks. |
| ENIL | `source/shared/ENILAccount.m`, `source/shared/enil_cocoa.m` | C worker callbacks, coalesced main-thread events, progress, and cancellation across account changes. |
| Strappy-Cocoa / Retro-Cloud-Sync | `source/macOS/StrappyServiceController.m` / `source/macOS-app/RCServiceController.m` | Native service control and status, alongside separate UI/helper signing and lifecycle configuration. |
| Retro-DLP / Retro-Cloud-Sync | `source/gui/iOS/tests/ios_ui_test.m`, `source/gui/macOS/tests/` / `source/tests/iOS/run-ui.py`, `source/tests/macOS/app/AppGUITestRunner.m` | Synthetic native UI fixtures, real controls, run-loop coordination, screenshots, and isolated test apps. |
| Strappy-Cocoa / ENIL | `source/daemon/tests/async_ui_device_probe.m`, `source/daemon/tests/async_ui_mac_probe.mk` / `source/tests/test_native_transport.py` | Async UI probes and offline transport fixtures that can support shared regression suites. |

### Library boundaries and compatibility contract

- [ ] Extend the existing `libs/cocoa/AltivecCocoa.h` surface incrementally;
  preserve its view/window/web/font helpers. Add opt-in Foundation services and
  separate AppKit/UIKit adapters. Keep reusable C mechanisms independently
  host-testable, with an explicit AltivecCore dependency for SQLite consumers.
  Do not require database, network, or daemon initialization for basic UI use.
- [ ] Make database support a separate optional `AltivecCocoaSQLite` library
  target. Keep UI helpers and generic event/table interfaces in `AltivecCocoa`;
  put SQLite-backed queries and change observation in `AltivecCocoaSQLite`,
  which links normally against AltivecCore for SQLite. Database consumers opt
  into both Cocoa targets and AltivecCore at build time; basic Cocoa consumers
  require no AltivecCore linkage. Use separate targets rather than weak linking
  for this dependency, preserving static-library support on legacy iOS. Keep
  generic interfaces usable with app-provided data sources and expose the
  optional module through its own header and explicit Make dependency.
- [ ] Publish a capability matrix covering compile SDK, deployment floor,
  runtime backend, permission/signing requirements, and fallback behavior.
  Preserve Tiger MRC and the current iOS 5 library floor; reconcile sibling
  iOS 4.3 claims before migration. Shared headers must not require blocks, ARC,
  modern Objective-C syntax, or unavailable framework symbols on legacy slices.
  Isolate newer implementations behind build guards and runtime dispatch.
- [ ] Specify ownership and shutdown for every callback/context, observer, and
  worker. Give subscriptions explicit invalidation, copy borrowed C payloads,
  deliver Cocoa events on the main thread, and discard stale generations after
  account changes or teardown. Never block the UI waiting for a worker to stop.

### Local notifications and notification activation

- [ ] Add `AILocalNotificationCenter`: authorization/capability reporting,
  explicit permission requests, immediate or scheduled requests with stable IDs,
  replacement/cancellation, badge updates, and activation callbacks with small
  app-owned routing payloads. Keep foreground presentation, message privacy,
  account selection, and notification wording as app policy.
- [ ] Start with ENIL and Retro-DLP's legacy wrappers; evaluate a modern
  UserNotifications backend separately from `UILocalNotification` and
  `NSUserNotification` paths. Declare which features each backend supports;
  report unsupported/unknown separately from denied. On systems without native
  notifications, offer an explicit in-app/delegate fallback without pretending
  a system banner was delivered. Verify SDK/link compatibility before promising
  a modern backend with the currently provisioned phone SDK.
- [ ] Distinguish local presentation from remote push transport. An SSE event
  that triggers a local alert is not APNs registration or a guarantee of delivery
  while suspended. Keep APNs credentials/server delivery and ENIL's transport
  outside this module. Distinguish scheduled cancellation from delivered-alert
  removal; do not promise reliable clearing based only on resetting a badge.
- [ ] Inject a recording backend for offline tests: verify permission denial,
  duplicate completion, scheduled cancellation, foreground suppression, badge
  changes, and activation after cold launch. Separately test real OS delivery
  and authorization on supported native targets.

API reference: [Apple User Notifications](https://developer.apple.com/documentation/usernotifications).

### Committed SQLite changes from C to Objective-C

Implementation update (2026-10-12): the optional `AltivecCocoaSQLite` target,
portable revision feed/owned writer/snapshot reader, `AIStoreObserver`, and
schema-independent `AIPagedRows` are implemented. Strappy and Retro-DLP now
consume these instead of their private journals/caches; ENIL uses the shared
bounded debounce. See [the migration contract](docs/sqlite.md) for delivered
coverage and the remaining full background-paging/table-adapter work. The
composite checklist items below remain open where rollout or coverage is partial.

- [ ] Add a small C change-feed contract and `AIStoreObserver` adapter carrying
  store identity, topic/table, stable record IDs, generation, and a full-refresh
  flag. Support both explicit application mutation notifications and an optional
  SQLite hook adapter; apps should only map their domain changes into this feed.
- [ ] Publish only after a successful transaction completes. Buffer/coalesce
  candidate changes; discard rolled-back changes, including savepoint rollback.
  Do not run SQL or Objective-C observers inside SQLite hooks, and do not treat
  a commit-hook invocation as proof that COMMIT succeeded. Make connection/hook
  ownership explicit so installation cannot silently replace another consumer.
- [ ] Treat update hooks as incomplete invalidation hints, not a universal row
  audit log: account for WITHOUT ROWID tables, REPLACE/delete behavior, and
  writes from other connections/processes. Use explicit post-commit reporting
  where exact coverage is required; fall back to query invalidation otherwise.
- [ ] Extract Strappy's bounded revision/cursor pattern for daemon consumers.
  Use an IPC adapter for wakeups and authoritative rereads of committed data;
  reconnect, missing scope, or journal overflow must cause full resync. Each
  observer advances its own cursor only after applying its result. Coalesce
  bursts without losing changes that arrive during a read; SQLite hooks alone
  cannot implement cross-process delivery.
- [ ] Port regression scenarios for rollback, savepoints, concurrent readers,
  two independent windows, daemon restart, overflow, observer disposal, and
  queued callbacks after account closure. Assert no notification exposes an
  uncommitted row and no subscriber depends on another subscriber's cursor.

SQLite documents the connection-local scope and omissions of
[update hooks](https://www.sqlite.org/c3ref/update_hook.html), and the reentrancy
restrictions of [commit/rollback hooks](https://www.sqlite.org/c3ref/commit_hook.html).

### Efficient SQLite-backed NSTableView and UITableView data sources

- [ ] Extract `AIQuerySnapshot` / `AIPagedRows` from Retro-DLP's row collection
  and Strappy's refresh pipeline. Apps provide parameterized count/page/seek
  queries, identity mapping, and section definitions. The library owns reader
  lifetime, statement reuse, bounded caches, cancellation, and generation checks;
  it should not become an ORM or assume a particular schema.
- [ ] Keep count, sections, and pages consistent within a read snapshot. Use
  stable sort keys with a unique tie-breaker, matching indexes, and seek paging
  for sequential scrolling. Support arbitrary table row access via measured
  offset queries or sparse anchors, rather than assuming scrolling is always
  sequential. Test NULLs, duplicate sort values, descending order, and deletes.
- [ ] Fetch missing pages and expensive counts off the main thread; table
  callbacks return cached rows/placeholders and schedule bounded prefetch.
  Avoid one SQL query per cell and loading every row as an NSDictionary.
  Release old snapshots promptly to limit WAL retention; keep migrations and
  writes off UI reader connections. Surface read errors instead of empty data.
- [ ] Add thin AppKit/UIKit adapters that preserve selection and scroll anchors
  by identity. Apply safe insert/delete/reload batches where supported and a
  coalesced reload fallback on older systems. Discard results for obsolete
  filters/generations and keep pending edits independent of fetched snapshots.
- [ ] Add deterministic large fixtures and benchmarks for initial display,
  sequential scroll, random jumps, sorting/filtering, and concurrent writes.
  Record query counts/plans, cache bounds, UI stalls, and retained WAL size;
  establish budgets on a legacy device before declaring a performance win.
  Keep app-specific indexes and query-plan assertions in the consuming app.

See SQLite's [scrolling-window queries](https://www.sqlite.org/rowvalue.html#scrolling_window_queries)
for the cost of deep OFFSET scans and the seek-paging alternative; select SQL
syntax supported by the actual bundled SQLite version.

### Background work, progress, and service lifecycle

- [ ] Add `AIBackgroundWorkCoordinator` with explicit work tokens, operation
  counts, cancellation, checkpoint/resume delegates, and exactly-once finish.
  Start with Retro-DLP's finite iOS allowance and ENIL's assertion cleanup.
  Handle expiration, rejected allowances, foreground return, and completion
  racing expiration without leaking a task or starting new work after expiry.
- [ ] Keep finite UIKit execution, platform-specific background modes, Mac
  sleep/wake, and launchd services as separate backends/capabilities. Persistent
  jobs need app-owned durable checkpoints and restart recovery. Do not turn
  ENIL's legacy VoIP behavior into a general-purpose background guarantee or
  silently add background modes/private entitlements to consumer apps.
- [ ] Extract shared progress/error delivery into a small operation adapter:
  bounded main-thread updates, stable operation IDs, terminal results, and
  cancellation that prevents late UI updates. Leave retry/idempotency decisions
  with the app; interrupted mutations may have an unknown outcome.
- [ ] Pilot `AIServiceClient` status/control adapters in Strappy and rCloud:
  readiness, timeout, reconnect, stop acknowledgement, and bounded log tails.
  Keep service installation and privilege decisions in the existing package
  tooling. Test with isolated fake services and restart/failure injection.

Reference: [Apple's finite background execution guidance](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time).

### Entitlements, signatures, and capability diagnostics

- [ ] Extend `make/sign.mk`, bundle signing, and `validate-package` rather than
  adding a second signer inside AltivecCocoa. Define declarative per-product
  capability profiles that resolve to reviewed entitlements, Info.plist keys,
  and signing inputs for the app, each helper, and test bundles independently.
  Preserve explicit overrides and sandbox/rootful/rootless distinctions.
- [ ] Validate the built artifact's embedded entitlements and signature against
  the declared profile, including nested executables and slices. Distinguish
  jailbreak/ad-hoc signatures from provisioned identity requirements; report
  unsupported signing combinations instead of implying installation acceptance.
  Keep signing keys and provisioning material outside generated source.
- [ ] Expose small runtime capability/error diagnostics in AltivecCocoa so apps
  can distinguish unavailable APIs, denied permissions, and service failures.
  Test stable application identity/privacy-grant behavior across rebuilds on
  native systems; structural signature checks alone cannot establish it.

### Offline native UI test support

- [ ] Create an optional `AltivecCocoaTestSupport` target, excluded from release
  products. Extract predicate-based run-loop waits with deadlines, assertions,
  fixture setup/cleanup, screenshots, and structured results from Retro-DLP and
  rCloud. Apps should supply scenarios and small fake model/service adapters.
- [ ] Provide AppKit and UIKit example suites using real production controllers
  with seeded SQLite stores, local assets, fake clocks, notification recorders,
  and injected workers/transports. Fail unexpected network requests; use
  loopback fixtures only when testing transport. Require no live accounts,
  credentials, service APIs, media downloads, or fixture fetches during tests.
- [ ] Run controller/action tests inside a native test app on old OS versions;
  retain Accessibility/event-driven UI coverage where available and optional
  modern XCTest adapters. Label controller tests separately from actual input,
  OS notification, suspension, and installation tests. Offline does not mean
  a UIKit/AppKit runtime can execute on Linux.
- [ ] Give each run isolated databases, defaults, bundle IDs/Keychain items,
  notification IDs, and service endpoints. Clean up only owned fixtures and
  retain failure evidence. Reuse explicit host/staging inputs and timeouts from
  section 6; avoid hard-coded personal devices or a new deployment framework.
- [ ] Share scenarios for empty/error/loading lists, burst refreshes, selection
  preservation, notification activation, expiration/completion races, service
  reconnection, and window/controller teardown. Report tested OS/architecture
  and skipped native coverage separately from portable or cross-build results.

### Follow-on candidates and delivery gates

- [ ] Audit ENIL's `ENILKeychain` and Strappy's `XPKeychain` for a narrow shared
  credential-store API with explicit namespaces, update/delete behavior, and
  native error reporting. Keep account formats, login flows, access groups, and
  secret migration policy in apps; inject a memory store for offline UI tests.
- [ ] Evaluate bounded asset loading/caching using ENIL's `enil_asset_cache` and
  Retro-DLP's thumbnail consumers: cancellation on row reuse, deduplicated
  requests, byte limits, atomic cache writes, and main-thread publication.
  Extract only after a second consumer validates the same contract.
- [ ] Deliver in small slices: notification service plus recording tests first;
  committed-change feed next; paged rows/table adapters next; background/service
  adapters and capability profiles afterward. Build offline test support with
  each slice rather than postponing it to a final infrastructure project.
- [ ] For each module, migrate one pilot app, then a second independent consumer,
  recording removed wrappers/lines and the remaining app configuration. Audit
  licenses before moving source. Keep compatibility wrappers until migration is
  verified; update public headers, library packaging, docs, and optional
  `cocoa-shared`/`cocoa-daemon` examples together.

**Done when:** at least two consumers use each promoted module without copied
threading/compatibility machinery; relevant portable, cross-build, and offline
native regressions pass; capability fallbacks are documented and exercised;
and individual apps visibly delete infrastructure code while retaining their
own business behavior. No sibling migrations or runtime changes are part of
this planning-only update.

## Suggested delivery order

1. Release CLI/help and migration fixtures; separate preparation from Git and
   publication. This removes the immediate credential friction.
2. Root-output fixes in the existing common Makefiles, including IPA packaging;
   validate ENIL and Retro-DLP workarounds can be retired in follow-up app changes.
3. Remove altivec-deploy and update docs/image dependencies.
4. Extract product/package modules and generate basic Mac/iOS/shared-core apps.
5. Add daemon, rootful/rootless, CLI/library templates and artifact validators.
6. Expand native test evidence, migrate sibling projects individually, then
   consolidate remaining sample/library/toolchain output paths.

For each step, keep existing consumers working through documented compatibility
entry points or a coordinated migration. This TODO changes only the plan; sibling
repositories, releases, device installations, and the container remain unchanged.
