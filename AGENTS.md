# Developing AltivecIntelligence

This file is for work on the AltivecIntelligence repository: its build engine,
CLIs, shared libraries, templates, and container image. App-project defaults
live in `templates/AGENTS.md`; the chooser copies that file into a user's working
directory only when no `AGENTS.md` entry exists. Do not copy this maintainer guide
into app projects. Existing project instructions are never refreshed automatically.

## Repository map

- `altivec_common_*.mk` and `make/`: shared compilation, product graphs,
  resources, signing, packaging, and output management.
- `bin/`: SDK discovery/installation, chooser, and source-checkout CLI entries.
- `packages/altivec-app/`: dependency-free Node project generator and offline
  templates. `packages/altivec-release/`: local-first release CLI.
- `libs/core/`: bundled C dependencies and AltivecCore packaging.
- `libs/cocoa/`: shared UI, Keychain, notifications, paging, and collection APIs.
- `libs/cocoa-sqlite/`: portable SQLite snapshots/change feeds and Cocoa observers.
- `templates/`: app-project Compose setup and default agent guidance.
- `apps/`: small build fixtures; prefer generated projects for onboarding.
- `Containerfile`, `docker/`, and `toolchain/`: image construction, smoke tests,
  and optional native-device tooling.
- `test/`, library test directories, and `.github/workflows/`: validation.
- `docs/`: feature contracts and deployment recipes. `TODO.md`: remaining work
  and historical evidence, not proof of tests passing on the current checkout.

## Working on the engine

Use the actual checkout as the source of truth. Inside the image, `/altivec`
contains the engine and `/repo/user` normally contains a separate mounted app.
Do not assume those paths exist on a host checkout. For ordinary engine changes,
mount this checkout at `/altivec` in an existing image with the SDK volumes;
a full image rebuild is unnecessary. Image contents and installed npm packages
still require separate validation when changed.

Keep app Makefiles declarative. Build mechanics belong in shared Make modules;
discoverable developer commands belong in the Node CLIs. Preserve offline
operation and SDK-free CLI/website workflows. Prefer small, focused changes.
See `docs/make-products.md` and `docs/app-templates.md` before changing contracts.

Preserve root output conventions, safe cleanup, parallel-build isolation,
per-product signing, and explicit platform/architecture choices. Do not change
prebuilt library paths without coordinated consumer migration. Extend existing
signing/package validation rather than adding another signer in AltivecCocoa.

## Compatibility and source conventions

Shared Apple code must preserve Mac PPC/i386 10.4, x86_64 10.9, arm64 11.0,
and iOS armv7 5.0 / arm64 7.0 compiler floors. These are not native coverage
claims. Legacy Mac builds use Apple GCC 4.2.1 and the 10.5 SDK; modern Mac and
iOS use Clang with the 11.3 and 8.4 SDKs respectively. Inspect
`altivec_toolchains.mk` and `make/` for current compiler paths and flags.

Keep Tiger-compatible Objective-C under MRC, with explicit ivars/accessors,
bracket syntax, and no required properties, blocks, ARC, or GCD. Isolate modern
syntax to compatible source groups. Check both header availability and runtime
availability; a declaration in the 10.5 SDK does not establish Tiger support.
Follow existing runtime-gated compatibility helpers and documented fallbacks.
App-level compatibility symbols use `XP`; shared public APIs use their module
prefix. Do not move app-specific policy into a generic compatibility shim.

Use two-space indentation, 80-column lines where practical, trailing underscores
for Objective-C ivars, and `k` for ordinary constants. Objective-C method
implementations use a semicolon after the signature, then a brace on a new line:

```objectivec
- (void)dealloc;
{
  [value_ release];
  [super dealloc];
}
```

Document public API ownership, thread affinity, cancellation, and invalidation.
Pointers are not implicitly owned under MRC. Retain/copy owned values and release
them; copy stored strings. Borrowed targets/delegates require explicit lifetime
management. Report non-deprecation warnings and their compatibility implications.
Preserve the existing build-log indentation and `>` detail style.

## Shared library changes

Read the relevant contract before adding or migrating APIs:
`docs/keychain.md`, `docs/notifications.md`, `docs/sqlite.md`, and
`libs/cocoa/COLLECTIONS.md`. Keep portable C consumers independent of Foundation.
Keep SQL/schema, credential identity, notification wording, and business policy
in apps. Preserve post-commit publication, bounded caches, stale-generation
suppression, and explicit teardown in the existing data/collection APIs.

Promote new abstractions only when real consumers demonstrate repeated mechanics
that can be removed. Count shared code and remaining adapters against deletions;
tests are separate. Coordinate incompatible API changes with consumers, update
headers/packaging/docs, and test fallbacks on the oldest available runtime.

## Templates and chooser

Edit `templates/AGENTS.md` for app defaults. Keep generated project guidance in
`packages/altivec-app/lib/generate.cjs` consistent with it. Preserve the chooser's
exclusive-copy behavior for existing files, directories, and symlinks.
The Containerfile already copies `templates/` into `/altivec/templates/`.

Update both `templates/compose.yml` and its packaged copy together. The native
shell generator consumes `packages/altivec-app/templates/ios-device`; keep its
manifest aligned with `templates/catalog.json`. Preserve offline generation,
no-overwrite behavior, and reviewable upgrades. Do not overwrite app source when
updating templates. Keep artwork files and matching plist declarations together.

## Validation

Choose checks for the changed subsystem; inspect CI and local Makefiles for
additional required coverage:

- Chooser: `node --test test/altivec-chooser.test.cjs`.
- Generator: `node --test test/altivec-app.test.cjs` (includes package smoke).
- Release CLI: `node --test test/altivec-release.test.cjs`; migration fixtures
  require Python/PyYAML, normal CLI use does not.
- SDK discovery: `python3 -m unittest discover -s test -p 'test_sdk_discovery.py' -v`.
  Installation checks require Linux `flock`; BuildKit checks are opt-in.
- Make products: `python3 -m unittest discover -s test -p 'test_make_products.py' -v`.
- SQLite C layer: `make -C libs/cocoa-sqlite test`.
- Generated SDK matrix: `bash test/test_app_templates_container.sh` inside an
  existing image with SDK volumes and current modules mounted at `/altivec`.
- Cocoa/native changes: use the relevant library and consumer native harnesses;
  follow their documented host/staging inputs and deployment recipes.

Run portable checks first. Report cross-builds, package inspection, native
runtime tests, and skipped coverage separately. Never infer device behavior
from compilation, or published-image behavior from a mounted checkout test.
Keep native runs isolated below `~/Desktop` on Mac or `~/tmp_altivec` on iPhone;
clean only owned fixtures and preserve failure logs. Use `docs/deployment.md`.

## Release and image work

Keep release preparation independent of Git identity, credentials, and remotes.
`prepare`, `build`, and `stage` precede explicit host commit/publication;
`bump` remains preparation-only. See `packages/altivec-release/README.md`.
Never publish an image, package, commit, or tag without user authorization.
Do not install SDKs or rebuild the full image merely for documentation/CLI work.
Use image smoke checks for image changes and record exactly what was rebuilt.
