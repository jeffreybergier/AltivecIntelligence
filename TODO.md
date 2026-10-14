# AltivecIntelligence improvement plan

Initial repository review: 2026-10-10. Reconciled on 2026-10-14 against local
source and commits through 2026-10-13 in this repository and the four sibling
apps. Checked items record implemented behavior; unchecked items identify
remaining work or evidence gaps. Validation notes describe earlier runs, not
tests rerun during this documentation review.

The evidence table below preserves the original review baseline; its descriptions
of old release/build behavior are historical. Current status follows by section.

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
migrated. As of the 2026-10-14 review, ENIL, Retro-Cloud-Sync, Strappy-Cocoa,
and Retro-DLP also have `.altivec-release.json`; YAML migration fixtures remain
for older consumers. Original validation: 41 Node tests, workflow/template lint,
real-config dry-run, and installed-package smoke in the local image with Git
absent from PATH. The
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
- [x] Install the pinned, checked-in release/generator packages offline alongside
  templates and Make fragments from the same source checkout. The Containerfile
  checks package versions, CLI help, and template discovery.
- [ ] Extend final-image smoke coverage to verify packaged contents and generated
  project/module compatibility together; existing recipe and package checks do
  not establish that every published image passed this complete check.
- [ ] Rewrite README/AGENTS examples around generated projects and root commands.
  Reconcile documented deployment floors with actual compiler flags and device
  evidence: sibling guides mention iOS 4.3 while the container/device template
  guidance describes iOS 5.0. Do not advertise a broader tested matrix by inference.
- [ ] Keep tiny sample apps as build fixtures; make richer examples generated
  from supported templates so documentation and templates cannot drift apart.
  Replace duplicated CURL-wrapper teaching examples with a minimal direct-libcurl
  or shared-model example matching the current development guidance.

## 8. Extract shared application capabilities into AltivecCocoa

Capability review: 2026-10-12; implementation reconciliation: 2026-10-14.
Notifications, change feeds, paged rows, and collection adapters are implemented.
Background/service adapters, capability profiles, and a common native test
support target remain proposals. The goal is smaller app facades and controllers:
apps supply domain queries, row presentation, notification content, and job policy;
Altivec owns reusable
lifecycle, threading, compatibility, and delivery mechanics. Not every app
needs every module. Names of unimplemented modules remain provisional.

### Evidence and first consumers

This table records the original extraction sources, including wrappers since
removed. Paths are relative to the sibling repositories in the first column.

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

### Recent consumer evidence

The following commits were reviewed against current source. Release commits are
checkout context, not proof of published artifacts or device validation.

| Repository / reviewed HEAD | Relevant commits and current behavior |
| --- | --- |
| AltivecIntelligence `972de49` | `7ea3ae1` adds SQLite infrastructure; `48f2ac9` adds notifications; `5c4ae77` / `34967f9` add collections, forms and outlines. `72c3412` fixes identity hashing; `55b8259` makes refresh explicit; `259902e` documents Retro-DLP's bounded synchronous reads. |
| ENIL `2917e94` | `6e8e3e0`, `36f71d0`, and `0a14655` adopt debounce, notifications, and table adapters. `db60f0b` adds bounded SQLite roster pages and data-change refreshes; settings load before their initial snapshot (`d0368e8`). |
| Retro-Cloud-Sync `7ac0a14` | `2ee6898` adopts collection forms. `40f5f96` initializes settings early and replaces the log table with `RCLogViewController`, a scrolling text view with a bounded 1 MiB tail; initial loading is synchronous and later refreshes use the shared worker. |
| Strappy-Cocoa `706adac` | `b58bad2`, `9fb0272`, and `7618a34` adopt shared observers, caches, and collections. `4a0e232` prepares initial sources synchronously and resolves cell text through bounded synchronous reads. `76a89dc` removes loading states around inline control commands; later credential/catalog fixes remain app behavior. |
| Retro-DLP `8eee459` | `9aa7587`, `70403bb`, and `467d144` adopt SQLite and collection helpers. `5521ecd` prepares sources before presentation; `c360772` restores bounded synchronous cell-text reads, superseding the earlier placeholder rollout. `1059d9e` caches Mac status icons. `2baa42a` / `8eee459` fix release asset provisioning and attribution. |

### Library boundaries and compatibility contract

- [x] Extend `libs/cocoa/AltivecCocoa.h` with opt-in Foundation services and
  AppKit/UIKit adapters while preserving view/window/web/font helpers. Basic
  Cocoa use requires no database, network, or daemon initialization.
- [x] Ship the independent static `AltivecCocoaSQLite` target, umbrella header,
  packaging, and explicit `<Product>_SQLITE` Make dependency. Consumers specify
  CORE linkage; Objective-C collection/paging consumers also select COCOA.
  C-only consumers can omit COCOA. Generic row/table interfaces remain in
  AltivecCocoa without an AltivecCore dependency; no weak linkage is required.
- [x] Document implemented backend/floor/fallback matrices in
  [notifications](docs/notifications.md) and [SQLite](docs/sqlite.md). Shared
  APIs retain Tiger MRC and iOS 5 armv7 / iOS 7 arm64 floors, with runtime-gated
  platform behavior and no blocks/ARC requirement.
- [ ] Reconcile stale iOS 4.3 claims in sibling guides with their current iOS 5
  build floor. Extend capability documentation when new backends or signing
  profiles land; do not infer native coverage from cross-builds.
- [x] Document borrowed targets, copied payloads, explicit invalidation, main-thread
  delivery, cancellation, and stale-generation suppression for the implemented
  observers/workers. See the module headers and
  [collection lifetime contract](libs/cocoa/COLLECTIONS.md).
- [ ] Apply the same ownership/shutdown contract to future background and service
  adapters, including nonblocking teardown and expiration races.

### Local notifications and notification activation

Implemented in `48f2ac9`; see [the notification contract](docs/notifications.md).
ENIL (Mac/iOS) and Retro-DLP (iOS) use immediate background-only alerts.

- [x] Provide `AILocalNotificationCenter` authorization/capability reporting,
  explicit permission requests, immediate alerts, badges, activation routing,
  foreground suppression, and automatic app-wide foreground cleanup. Remove
  the consumers' private notification implementations.
- [x] Implement legacy AppKit/UIKit backends with distinct unsupported, unknown,
  denied, suppressed, failed, and submitted outcomes. Document that submission
  does not prove display and local alerts do not provide APNs or suspended SSE
  delivery. Preserve ENIL's cancel-then-badge-zero sequence and Retro-DLP's
  nonzero alert badge; scheduled cancellation is not delivered-alert removal.
- [x] Add an injectable recording backend and deterministic native permission,
  lifecycle, cleanup-order, badge, cold-launch activation, error, and invalidation
  regressions, plus Retro-DLP production-delegate coverage.
- [ ] Verify actual notification-tray clearing and permission combinations across
  supported iOS versions. ENIL has a user-observed clearing result, but recording
  tests and that observation do not establish the full OS/permission matrix.
- [ ] Add scheduling, stable request IDs, replacement/per-notification removal,
  and configurable presentation policies, with cancellation and duplicate/racing
  completion regressions for those new APIs. Keep wording/privacy/routing in apps.
- [ ] Evaluate a modern UserNotifications backend against the provisioned SDKs;
  add an explicit app/delegate presentation fallback where native alerts are
  unsupported. The current backend reports Unsupported without fake success.

### Committed SQLite changes from C to Objective-C

Implemented in `7ea3ae1`; see [the migration contract](docs/sqlite.md).
Strappy uses the shared revision journal and observer; Retro-DLP uses shared
read snapshots and observation. Domain transactions and IPC remain app-owned.

- [x] Provide the portable `ai_store_feed` bounded revision journal with store
  identity, topics, numeric/copied text keys, generation, and full-resync hints.
  `AIStoreObserver` coalesces topic/scope invalidations on the main thread; exact
  record details remain in the C feed/authoritative reread.
- [x] Provide `ai_store_writer` with explicit connection/hook ownership and
  transaction/savepoint operations. Publish only after successful COMMIT;
  rollback, failed commits, and rolled-back savepoint candidates do not publish.
  Existing writers can explicitly publish after their own successful commit.
- [x] Treat optional update hooks as incomplete dirty hints, outside observer/SQL
  execution. Document WITHOUT ROWID, REPLACE/delete omissions and connection-local
  scope; use explicit domain reporting for exact coverage.
- [x] Extract Strappy's bounded cursor mechanism: independent consumer cursors,
  capture-before-read/acknowledge-after-apply ordering, and full resync for reset,
  overflow, or missing coverage. Strappy retains IPC wakeups/reconnect handling;
  SQLite hooks are not a cross-process transport.
- [x] Add portable regressions for rollback/savepoints, rejected commits,
  snapshot isolation, independent cursors, reset/overflow, racing publication,
  text identities, statement reuse, and WAL release. Native Foundation coverage
  checks observer invalidation, stale generations, and bounded debounce;
  ENIL consumes `AICoalescedCallback` for committed UI events.
- [ ] Complete app-level native evidence for two independent windows across daemon
  restart/reconnect and account teardown with callbacks in flight. Portable
  cursor/reset tests do not by themselves establish those full UI/IPC scenarios.

### Efficient SQLite-backed NSTableView and UITableView data sources

- [x] Extract the C `ai_query_snapshot` reader and schema-independent `AIPagedRows`.
  Readers pin committed data, reuse up to eight statements, support interruption,
  and release WAL snapshots on close. Apps own SQL, ordering/indexes, sections,
  identity mapping, and snapshot replacement; this is not an ORM.
- [x] Bound `AIPagedRows` to four 32-row pages, with random access, synchronous
  `objectAtIndex:`, and optional asynchronous placeholder requests. Async requests
  and deliveries are bounded, cancellable, and generation-checked. Invalid/short
  pages surface errors. Placeholder paging is an opt-in library capability.
- [x] Share refresh scheduling, cancellation, generation checks, page-observer
  lifetime, and table application through `AICollectionController`,
  `AICollectionSnapshot`, and AppKit/UIKit table/outline adapters. All shipping
  native tables across the four apps use adapters, including forms and the Mac
  playlist outline. rCloud's log is now a text view, not a table.
- [x] Add identity-only projections for Retro-DLP video/job queries, Strappy
  conversations/database catalogs, and ENIL rosters. Preserve selection and
  scroll anchors by identity, with incremental batches or safe reload fallback.
  Keep pending edits independent of snapshots and refresh forms explicitly.
- [x] Prepare initial consumer row sources before presentation and preserve them
  across navigation. Retro-DLP, Strappy, and ENIL resolve complete cell text
  synchronously through bounded pages; they do not require loading placeholders
  or later text patches. Data changes/explicit refreshes can build replacement
  sources on workers while current content stays visible. Appearance alone does
  not request a list reload. Retro-DLP retains its 128-row query cache and
  separate four-page display cache; action-time identity/file checks stay in apps.
- [x] Add 100,000-row portable/Foundation fixtures for query counts, random access,
  cache bounds, cancellation, snapshot isolation, and WAL release. Measure shared
  snapshot construction/diff costs on the host Mac and Tiger VM; fix identity-hash
  collisions and add unchanged/large-diff fast paths. See
  [benchmark scope and results](libs/cocoa/tests/BENCHMARKS.md).
- [ ] Move expensive collection diff computation off the UI thread, preserving
  stale-result rejection and native table application on the main thread. Tiger
  VM measurements still show 4,096-row small-edit diffs taking about 29–36 ms
  median before rendering; retain bounded large-list fallback.
- [ ] Measure end-to-end initial display, scrolling, random jumps, sorting/filtering,
  and concurrent writes on legacy devices. Record query plans/counts, memory/cache
  bounds, UI stalls, and retained WAL; establish budgets before changing limits
  or the consumers' deliberate synchronous cell-text policy. Existing microbenchmarks
  exclude SQL and native table rendering.
- [ ] Audit consumer query coverage for NULLs, duplicate sort values, descending
  order, deletes, and stable tie-breakers; retain app-specific index/query-plan
  assertions. The generic cache/reader tests do not prove every domain query.
- [ ] Close recorded native gaps: rerun rCloud's isolated UIKit suite after the
  runner timeout and establish coverage for its new text-log/settings behavior;
  distinguish unavailable optional GNUstep coverage from native Apple results.

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
- [x] Deliver notifications with recording tests, the committed-change feed, and
  paged rows/table adapters as separate slices with consumer migrations.
- [ ] Continue with background/service adapters and capability profiles, adding
  offline regression support with each slice.
- [x] Migrate notifications to ENIL/Retro-DLP, SQLite infrastructure to
  Strappy/Retro-DLP, and collection adapters to all four apps. Public headers,
  library packaging, and module contracts accompany the implemented slices.
- [ ] For future modules, validate a pilot and second independent consumer,
  audit source licenses, and record removed wrappers/remaining app configuration.
  Add optional shared-module examples to `cocoa-shared`/`cocoa-daemon`; the basic
  generated templates do not yet teach all of the new capabilities.

**Done when:** at least two consumers use each promoted module without copied
threading/compatibility machinery; relevant portable, cross-build, and offline
native regressions pass; capability fallbacks are documented and exercised;
and individual apps visibly delete infrastructure code while retaining their
own business behavior. Completed migrations above satisfy parts of this gate;
remaining module proposals and native evidence are tracked separately.

## Suggested delivery order for remaining work

Sections 1–6 are implemented in source, with the explicitly recorded native-evidence
gaps still open. The next sequence is:

1. Address measured UI-thread collection diff costs and establish end-to-end
   legacy-device budgets while preserving bounded synchronous cell-text behavior.
2. Close native evidence gaps for collections/settings/logs and notifications;
   extend template icon/launch coverage to iOS 5 and Leopard when available.
3. Finish section 7: generated-project onboarding, accurate deployment floors,
   tool discovery, final-image integration checks, and a website smoke test.
4. Extract background-work coordination with ENIL and Retro-DLP pilots, then
   service adapters and capability profiles. Add tests with each module.
5. Extend generated examples and consolidate remaining library/toolchain outputs
   only through an explicit consumer migration; prebuilt library paths remain
   an existing contract.

Keep existing consumers working through documented compatibility entry points
or coordinated migrations. This reconciliation changes documentation only;
validation, device installation, image rebuilding, and publication are separate
work and are not implied by the commit review.
