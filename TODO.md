# AltivecIntelligence improvement plan

Repository review: 2026-10-10. This is a proposed roadmap, not an implementation
or a claim that the proposed commands already exist.

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

- [ ] Implement a dependency-free Node CLI, packaged for installation through npm
  on a host as well as inclusion in the image. Pin the packaged version in the
  image; do not download the latest release helper on every invocation.
- [ ] Make no arguments print useful usage and examples. Support top-level and
  per-command `--help`, `--version`, `--dry-run`, and machine-readable output for
  inspection commands. Help must work outside a project, without SDKs or Git.
- [ ] Separate file preparation, local Git operations, and publication. Suggested
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
- [ ] Define what happens to old `bump` invocations: migrate documentation and
  callers, then make it a clearly documented local preparation alias or an
  actionable migration error. Never preserve implicit pushing as a surprise.
- [ ] `doctor` should distinguish missing checkout, missing identity, detached
  HEAD, unrelated dirty files, absent remote, and credentials not checked.
  Ordinary inspection/preparation must not probe the network. An explicit remote
  check should distinguish authentication/network failure from an absent tag.
- [ ] Print exact next steps for the current environment. Prefer preparing on the
  mounted checkout inside Docker and committing/pushing from the authenticated
  host. Offer optional SSH-agent forwarding or runtime token injection as
  documented alternatives, without baking secrets into images or copying a
  private key directory. Tokens do not configure Git author identity or SSH.
- [ ] Read the user's existing Git identity; accept explicit per-invocation
  identity when needed, without changing global configuration. Recheck version
  files, branch, tag availability, and unrelated staged changes before commit.
  Handle partial commit/tag/push failures with resumable steps, not a second bump.

### Configuration without npm dependencies

- [ ] Prefer a versioned `.altivec-release.json` schema, parsed with Node built-ins.
  Do not implement a partial YAML parser. Provide a one-time YAML-to-JSON
  converter using the existing Python/PyYAML environment during migration; the
  installed new CLI should need no npm libraries or PyYAML for normal operation.
- [ ] Address plist handling explicitly: Node has no built-in plist parser.
  Prefer generating version metadata from one plain version source and checked-in
  plist templates for new projects. For existing XML plists, implement and test
  a narrowly defined updater that validates every requested key and rejects
  unsupported formats before writing anything. Do not silently damage binary
  plists or introduce a hidden runtime dependency.
- [ ] Preserve named targets, custom workdirs, per-plist key lists, multiple
  artifacts, and asset-name substitutions. All four app repositories use these;
  Retro-DLP needs CLI, app, and library assets, while Strappy needs two DEBs.
- [ ] Preflight all version edits before applying any; use temporary files and
  recoverable writes. Validate destination paths and duplicate asset names before
  staging. Produce an artifact manifest with version, target, checksum, and
  provenance when available; a source archive must still work without Git.
- [ ] Support a non-plist version source for CLI/library and website projects.
  Keep build actions generic. Prefer executable-plus-argument arrays for new
  configuration, with explicitly marked shell actions for existing pipelines.
- [ ] Migrate CI together with configuration. Existing workflows call `ci-env`,
  `build`, and `stage`, validate `dist/*`, then use `gh release upload`. Retain
  `dist` compatibility or an explicit staging override while moving new defaults
  to `build/release`; do not silently break release globs.

**Done when:** preparation succeeds in an exported source tree and an
unauthenticated container; host commit/tag and explicit push are independently
usable; help explains both workflows; existing release configurations have
migration fixtures; mocked failures leave recoverable state and never push
implicitly. Include malformed versions/plists, unrelated staged files, duplicate
assets, detached HEAD, existing tags, and failed remote checks in CLI tests.

## 2. Retire altivec-deploy

- [ ] Remove `bin/altivec-deploy`, its dedicated test, `docs/altivec-deploy.md`, and
  debugger-init templates after auditing references in README, AGENTS, image
  checks, and examples. A temporary message-only compatibility stub is optional
  if existing users need a transition release.
- [ ] Replace the large deployment abstraction with short, editable recipes:
  transfer and launch a Mac bundle; install an IPA; install rootful/rootless DEBs;
  retrieve logs/crash reports; start and stop a test daemon. State prerequisites,
  package type, writable staging location, and cleanup ownership.
- [ ] Keep SSH/SCP/rsync and symbol generation. Audit `lldb` and other debugger-only
  image dependencies for removal; keep LLVM components needed by builds,
  analysis, and `dsymutil`. Debuggers can be documented as optional tools.
- [ ] Preserve project-specific native test runners. Removing deployment tooling
  should not remove automated device tests or force interactive debugging.

**Done when:** no template or agent guide recommends altivec-deploy; sample
artifacts still have documented manual install/run/log instructions; normal
builds and tests never require a debugger.

## 3. Make repo-root builds and composed products first-class

### One output convention

- [ ] Introduce explicit `PROJECT_ROOT` and `BUILD_ROOT`, resolved from the
  project's root Makefile or a generated project marker, not the shell's current
  directory or `git rev-parse`. Export the resolved absolute root to child makes.
  Use ENIL's implementation and build-system tests as the starting point.
- [ ] Default to this structure (a simple app can omit the product level):

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

- [ ] Fix public `release`, `debug`, `clean`, and `analyze` recipes to honor the
  selected root. Fix the phone IPA recipe's `../../$@` assumption with an absolute
  archive destination and isolated staging. ENIL and Retro-DLP should no longer
  need their private IPA workarounds.
- [ ] Keep build roots collision-free across products, configurations, platform,
  architectures, SDKs, and flags. Preserve relative source paths in object names
  so two `main.c` files do not collide. Track headers and resource changes;
  isolate ARC/MRC and generated-source inputs.
- [ ] Support safe clean scopes: current product/platform and explicit whole-root
  cleanup. Reject empty/root/source paths and dangerous symlink resolutions.
  Normalize relative overrides against PROJECT_ROOT. Either support whitespace
  consistently or reject it early with a precise explanation.
- [ ] Update release manifests, CI globs, `.gitignore`, sample docs, analyzer paths,
  and device scripts together. Migrate app outputs before touching prebuilt
  `/altivec/libs/*/build-{mac,phone}` locations, which are an existing consumer
  contract. Eventually consolidate image-build intermediates separately.

### Small reusable Make modules

Small application Makefiles are the critical measure of success. Each project
should declare its sources, products, dependencies, resources, and build options
in a short, readable Makefile; shared Altivec modules should own the build
mechanics. Moving complexity into project-local helper Makefiles or scripts
does not satisfy this goal.

- [ ] Split compilation, universal merging, resources, signing, and packaging
  into reusable fragments behind the existing common-Makefile entry points.
  Offer products for app, command-line executable, static library, and daemon,
  with explicit dependencies between them.
- [ ] Make architecture sets configurable. Support the full existing Mac and
  iOS matrices, legacy-only PPC/i386 (Retro-DLP), and single-slice development
  builds without overriding internal link rules. Declare SDK/deployment floors
  per slice and validate library slices before linking.
- [ ] Provide documented source groups and per-language/per-group flags for C,
  C++, Objective-C, and Objective-C++. Preserve Tiger MRC and optional ARC only
  in compatible iOS UI groups. Do not force one app's memory model on every app.
- [ ] Promote current ad hoc hooks into named inputs: extra static libraries,
  generated files, nested resource bundles, fonts/licenses, localizations,
  embedded executables, helper plists, entitlements, and package scripts. Keep
  an escape hatch, but make normal dependencies visible to Make.
- [ ] Provide packaging modules for Mac ZIP, sandboxed iOS IPA, and jailbreak
  rootful/rootless DEBs. Model install prefix, package architecture, ownership,
  compression, launchd definitions, and lifecycle hooks explicitly. Strappy's
  `Architecture: all` policy and rCloud's `iphoneos-arm` policy are project
  choices to validate, not a universal default to copy.
- [ ] Treat sandbox policy and package format as separate choices. A rootless
  install does not imply an unsandboxed application; Retro-DLP explicitly keeps
  its app container. Sign each executable with its own entitlements and test
  the resulting package, including embedded daemons/helpers.
- [ ] Add `make help`, `print-config`, `test-host`, `test-native`, and
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

- [ ] Add a dependency-free Node CLI with npm packaging. Include templates in the
  installed package/image so generation works offline. Proposed interface:

  ```sh
  altivec-app templates
  altivec-app new --template cocoa-shared --name MyApp \
    --bundle-id com.example.myapp --destination ./MyApp
  altivec-app new --help
  altivec-app doctor
  ```

- [ ] Publish template descriptions and their supported platform, architecture,
  minimum OS, memory model, package, and privilege combinations. Reject invalid
  combinations before creating files. Support noninteractive flags and a dry-run
  file list; optional prompts should not be required by agents.
- [ ] Preserve existing no-overwrite and path validation behavior. Render into a
  temporary directory, validate placeholders/metadata, then finalize. Generate
  project-specific README, AGENTS, root Makefile, ignore rules, release config,
  Compose setup, and test entry points with working examples.
- [ ] Share template assets and a small declarative template manifest between
  container and device tooling. Keep a shell-compatible on-device generator for
  old iPhones unless a supported Node runtime is actually demonstrated there.
  Share a project contract, not hard-coded compiler paths: container cross-build
  and `/var/altivec` native-device backends remain distinct.
- [ ] Record template/schema version in generated metadata. Later upgrades should
  produce a reviewable diff; never overwrite application code automatically.

### Initial template families

| Template | Scope and inspiration |
| --- | --- |
| `ios-basic` | Existing altivec-app starter: sandboxed, programmatic UIKit, shared C model, icons, launch images, localization, IPA. |
| `mac-basic` | Updated SingleWindow with tested nibless window lifecycle, MRC, selectable legacy/full architecture matrix, ICNS and ZIP. |
| `cocoa-shared` | ENIL/Retro-DLP structure: portable C model, a narrow Objective-C facade, AppKit/UIKit frontends, compatibility helpers, host tests. Optional SQLite/libcurl example with correct CA-bundle lookup. |
| `cocoa-daemon` | Strappy/rCloud structure: UI plus helper, explicit IPC boundary, separate entitlements, launchd/lifecycle files, rootful/rootless options where supported. |
| `daemon` | Headless service plus tiny test client; no mandatory GUI. Rootful iOS packaging and Mac launchd variants, with privilege and installation instructions. |
| `cli-library` | Retro-DLP structure: portable public C API, CLI consumer, Linux harness/sanitizers, Apple cross-builds, headers/library/license packaging. |

- [ ] Start with basic Mac/iOS and shared-core templates; add daemon/CLI families
  after the build modules stabilize. Compose optional networking, SQLite,
  localization, and daemon features rather than copying every combination into
  a separate full app. Extract minimal examples, not the applications' business
  logic, credentials, protocol integrations, or large dependency trees.
- [ ] Generate explicit compatibility boundaries like XPAppKit/XPUIKit and
  XPFoundation, with a small tested example. Audit extracted code and licenses.
  Keep app-specific compatibility policy out of universal template assumptions.

### Artwork and packaging that survive old devices

- [ ] Ship valid placeholder artwork and an explicit asset-generation command.
  Generate legacy iOS icon sizes, matching plist declarations, phone/tablet
  launch images for the selected support profile, and legacy ICNS representations.
  Reuse the device starter and Retro-DLP checks instead of assuming modern asset
  catalogs or storyboard compilation are available in Linux.
- [ ] Keep generated artwork as ordinary project resources; normal builds should
  not regenerate it. Validate declared files, image dimensions, ICNS element
  structure, localization encoding, and bundle identifiers.
- [ ] Carry forward Retro-DLP's documented Leopard limits (300,000 bytes per ICNS
  element and 1,000,000 bytes total) as a tested compatibility profile. Verify
  icon rendering and launch behavior on the actual oldest supported OS.
- [ ] Distinguish zero npm dependencies from zero external tools: asset conversion
  can invoke a documented image tool already provided by the environment.
  `doctor` should report missing converters, signing tools, and SDKs by feature.

**Done when:** each supported template can be generated offline, built, analyzed,
packaged, and host-tested without hand-editing paths; its native backend is tested
on a supported device where claimed; a second generation never overwrites files.

## 5. Make validation useful to agents and humans

- [ ] Provide layered test recipes: portable C/Linux tests first, cross-build and
  artifact checks next, native integration and UI smoke tests explicitly selected.
  Successful Linux tests or cross-compilation must not be reported as device
  launch, rendering, sandbox, or daemon-lifecycle validation.
- [ ] Borrow offline harness patterns from Strappy, ENIL's loopback tests, rCloud's
  portable/native separation, and Retro-DLP's external consumer and sanitizer
  checks. Keep live-service tests opt-in and separate from default tests.
- [ ] Use small project-owned SSH test scripts with explicit host and staging
  directory settings, timeouts, exit status, and log collection. Do not recreate
  altivec-deploy as a mandatory remote orchestration framework. Do not bake local
  host aliases or personal devices into generated templates.
- [ ] Add package inspection for slices/deployment targets, dynamic dependencies,
  symbols, plists, entitlements, resource/license presence, archive layout, and
  DEB metadata/lifecycle paths. Native tests should cover launch, IPC readiness,
  restart, upgrade, uninstall, and preservation of user data where applicable.
- [ ] Test the generator/release CLIs with Node's built-in test runner. Add a small
  generated-project matrix in CI, with SDK-dependent jobs clearly separated from
  dependency-free CLI and Linux harness tests. Reuse existing on-device
  `ios-app-make-check.sh` and `device-ios-app-smoke-test.sh` where appropriate.

## 6. Image and documentation follow-through

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
