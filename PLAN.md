# ENIL-cocoa Customization Migration Plan

This plan tracks reusable work discovered in `/repo/ENIL-cocoa` that should be
folded back into `/repo/altivec`. Work through these one at a time, keeping
changes surgical and preserving Tiger/Leopard and iOS 4.3 compatibility.

## Ground Rules

- Prefer reusable Altivec helpers, libraries, templates, or documentation over
  copying ENIL app code wholesale.
- Keep generated build outputs out of app repositories.
- Preserve manual memory management for Mac 10.4/10.5-compatible code.
- Build and report warnings after each migration. Deprecation warnings are
  expected; other warnings need attention.
- When extracting ENIL code, remove ENIL-specific names, log tags,
  notification names, and LINE assumptions before landing it in Altivec.

## Already Upstreamed

These ENIL needs are already represented in Altivec's common build files:

- [x] Mixed `.m` and `.c` support through `SOURCES` and `EXTRA_SOURCES`.
- [x] `ANALYZE_DIRS` source resolution for files found through `vpath`.
- [x] `VALIDATE_PATHS` preflight checks.
- [x] AltivecCore auto-detection and `ALTIVECCORE_REQUIRED` bootstrap.
- [x] AltivecCore static linkage for phone apps and static/dynamic linkage for
  Mac apps.
- [x] macOS AltivecCore framework bundle for libcurl, OpenSSL, zlib, SQLite,
  and cJSON.
- [x] macOS `EXTRA_BUNDLE_STEPS` for app-specific bundle staging.

## Migration Backlog

- [x] **SQLite library builder**
  - Source: `/repo/ENIL-cocoa/source/deps/sqlite/`.
  - Moved the quad-fat Mac and universal iPhone SQLite recipes into
    `/repo/altivec/libs/sqlite/`.
  - Added Altivec-level outputs at `libs/sqlite/build-mac` and
    `libs/sqlite/build-phone`.
  - Folded SQLite into app-facing `ALTIVECCORE_REQUIRED`,
    `ALTIVECCORE_LINKAGE`, and `ALTIVECCORE_DIR` instead of adding a separate
    `SQLITE_REQUIRED` path.
  - Preserved legacy flags, especially `HAVE_STDATOMIC_H=0` for PPC/i386 GCC.
  - Acceptance: an app can link SQLite through AltivecCore without carrying
    local SQLite build recipes or generated outputs.

- [x] **Phone bundle extension hooks**
  - Source: `/repo/ENIL-cocoa/source/iOS/Makefile`.
  - Added a phone-side equivalent to macOS `EXTRA_BUNDLE_STEPS`, with
    `PHONE_EXTRA_BUNDLE_STEPS` for phone-only staging.
  - Added `BUNDLE_FONT_DIRS` and `BUNDLE_LOCALIZATION_DIRS` so shared fonts and
    `.lproj` resources can be staged before IPA packaging.
  - Added opt-in `PHONE_LDID_SIGN` / `PHONE_LDID_ENTITLEMENTS` support so
    normal unsigned builds still work.
  - Acceptance: ENIL's iOS font/localization/signing hooks can be expressed
    through common Altivec variables instead of order-only local Make rules.

- [x] **Shared localization/resource staging pattern**
  - Source: ENIL macOS and iOS Makefiles.
  - Implemented `BUNDLE_LOCALIZATION_DIRS` for shared resource directories used
    by both Mac and iPhone targets.
  - Preserved the important platform split:
    - Mac Tiger/Leopard bundle copies of `Localizable.strings` need UTF-16 LE
      with BOM.
    - iOS can copy UTF-8 `.strings` files verbatim.
  - Acceptance: a new app can share `Resources/*.lproj` across Mac and iPhone
    without hand-writing the transcoding/copy rules.

- [x] **AltivecCocoa controller library**
  - Source:
    - `/repo/ENIL-cocoa/source/macOS/AIViewController.*`
    - `/repo/ENIL-cocoa/source/macOS/AICookieCutterWindowController.*`
    - `/repo/ENIL-cocoa/source/macOS/AIWebViewController.*`
  - Package as a Mac quad-fat `libAltivecCocoa.a` and
    `AltivecCocoa.framework`, plus an iPhone `libAltivecCocoa.a` carrying the
    cross-platform Font Awesome helper and font resources.
  - Keep `XPFoundation`, `XPAppKit`, and `XPUIKit` out of the library.
  - Added app opt-in through `ALTIVECCOCOA_REQUIRED`,
    `ALTIVECCOCOA_LINKAGE`, and `ALTIVECCOCOA_DIR`.
  - Acceptance: Mac apps can opt in with `ALTIVECCOCOA_REQUIRED=1` and use the
    three-pane nibless controller stack without copying ENIL sources; iPhone
    apps can require the static library without embedding unsupported
    frameworks.

- [x] **Font Awesome optional icon helper**
  - Source: `/repo/ENIL-cocoa/source/shared/FontAwesome.*`,
    `/repo/ENIL-cocoa/source/tools/gen_faicons.py`, and bundled OTF files.
  - Migrated as `AIFontAwesome` inside `AltivecCocoa`.
  - Renamed public symbols to the Altivec namespace (`AIFontAwesome`,
    `AIFontAwesomeIcon`, `AIFontAwesomeStyle`, `AIFA...` enum values).
  - Kept generated Solid icon enum regeneration through
    `libs/cocoa/tools/gen_aifontawesome_icons.py`.
  - Preserved Core Text rendering on 10.5+/iOS and ATSUI fallback on Tiger.
  - Static phone linkage stages OTF files into the app bundle; dynamic Mac
    linkage keeps OTF files inside `AltivecCocoa.framework`.
  - Bundles a Font Awesome Free / SIL OFL 1.1 notice alongside the OTF files.
  - Acceptance: apps can render Font Awesome icons through AltivecCocoa without
    copying ENIL helper code or writing custom font staging rules.

- [x] **Release helper**
  - Source: `/repo/ENIL-cocoa/scripts/version-bump-push.py` and `RELEASE.md`.
  - Added `/repo/altivec/bin/altivec-release` as a YAML-driven helper for app
    version checks, explicit version sets, patch/minor/major bumps, commit,
    tag, optional push, CI tag validation, target builds, and artifact staging.
  - Added `templates/altivec-release.yml` for project-specific plist paths,
    build commands, and release asset names.
  - Added `templates/github-release.yml` so app repos can publish configured
    release assets without hardcoded ENIL source paths.
  - Acceptance: a template app can opt into shared release versioning without
    adopting ENIL-specific paths or names.

## Do Not Migrate

- LINE protocol, sync, database schema, QR login, and SSE engine code.
- ENIL UI controllers, message rendering, sticker-specific behavior, and CSS,
  except as reference material.
- ENIL notification names, account/session paths, worker credentials, or
  product text.
- `XPFoundation.*`, `XPAppKit.*`, and `XPUIKit.*`. These compatibility shims
  are too ENIL-shaped and incomplete for AltivecCore or AltivecCocoa.
- A separate nibless AppKit controller template. The reusable controller code
  already landed in AltivecCocoa.
- ENIL's lower-priority pure-C utility helpers around `enil_strbuf.*` and
  `enil_cocoa.m`.

## Cleanup Targets In ENIL After Migration

- Point ENIL at `/altivec/libs/sqlite/build-{mac,phone}` instead of local
  SQLite outputs.
- Remove ignored SQLite generated outputs from `/repo/ENIL-cocoa` after the
  Altivec SQLite library is available.
- Replace local iOS order-only bundle/signing rules with common Altivec hooks.
