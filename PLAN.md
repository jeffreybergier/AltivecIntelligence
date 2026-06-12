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
- [x] AltivecCore static/dynamic linkage selection.
- [x] AltivecCore framework bundle for libcurl, OpenSSL, zlib, SQLite, and cJSON.
- [x] macOS `EXTRA_BUNDLE_STEPS` for app-specific bundle staging.

## Migration Backlog

Compatibility shims from `XPFoundation`, `XPAppKit`, and `XPUIKit` are
deferred for now. They are not complete enough to embed in AltivecCore or
AltivecCocoa, but the extraction notes remain below in case a future app needs
specific pieces.

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

- [ ] **Foundation compatibility library**
  - Source: `/repo/ENIL-cocoa/source/shared/XPFoundation.*`.
  - Extract generic pieces:
    - `NSInteger`/`NSUInteger` compatibility aliases for old SDKs.
    - Tiger-safe run-loop common-modes constant.
    - `NSFileManager` wrappers for create/copy/remove/list/trash operations.
    - percent-decoding and byte-count string helpers.
    - cross-platform internet-password keychain wrapper.
  - Remove or rename `ENILLog` usage before landing.
  - Acceptance: apps can include one Altivec Foundation compatibility header
    instead of re-implementing Tiger/iOS-safe wrappers.

- [ ] **AppKit compatibility library**
  - Source: `/repo/ENIL-cocoa/source/macOS/XPAppKit.*`.
  - Extract generic SDK/runtime shims:
    - dummy protocol pattern for pre-10.6 SDKs.
    - renamed constants for window masks, button styles, text alignment,
      table styles, colors, and toolbar identifiers.
    - safe runtime dispatch wrappers for modern AppKit selectors.
    - layer-backed view helpers that avoid requiring QuartzCore imports.
    - split view, sheet, file wrapper, image drawing, notification, and Dock
      badge helpers.
  - Decouple from `AICookieCutterWindowController`; the runtime tier helper
    probably belongs in the AppKit compatibility layer, not the cookie cutter.
  - Acceptance: Mac apps can use modern-looking AppKit affordances while still
    compiling against the 10.5 SDK and running on Tiger/Leopard.

- [ ] **UIKit compatibility library**
  - Source: `/repo/ENIL-cocoa/source/iOS/XPUIKit.*`.
  - Extract iOS 4.3-safe wrappers:
    - `UIWebView` scroll view access.
    - transparent web view/background helpers.
    - UIWebView shadow removal.
    - deprecated local notification wrapper.
    - badge count helper.
  - Remove ENIL-specific colors or make them app-supplied.
  - Acceptance: iPhone apps targeting iOS 4.3 can keep availability/deprecation
    handling out of controllers.

- [ ] **Nibless AppKit controller template**
  - Source:
    - `/repo/ENIL-cocoa/source/macOS/AIViewController.*`
    - `/repo/ENIL-cocoa/source/macOS/AICookieCutterWindowController.*`
    - `/repo/ENIL-cocoa/source/macOS/AIWebViewController.*`
  - Extract as an advanced Mac template or optional support library:
    - `NSResponder`-rooted view controller base.
    - runtime `NSViewController` adapter for modern split APIs.
    - three-pane split window controller with legacy `NSSplitView` fallback.
    - WebKit1/WKWebView bridge for file-backed HTML UIs.
  - Remove ENIL defaults and rename types if they become Altivec-owned.
  - Acceptance: a new Mac app can start from a Tiger-safe three-pane template
    without copying ENIL UI code.

- [x] **AltivecCocoa controller library**
  - Source:
    - `/repo/ENIL-cocoa/source/macOS/AIViewController.*`
    - `/repo/ENIL-cocoa/source/macOS/AICookieCutterWindowController.*`
    - `/repo/ENIL-cocoa/source/macOS/AIWebViewController.*`
  - Package as a Mac quad-fat `libAltivecCocoa.a` and
    `AltivecCocoa.framework`, plus an iPhone `libAltivecCocoa.a`/framework
    currently carrying the cross-platform Font Awesome helper.
  - Keep `XPFoundation`, `XPAppKit`, and `XPUIKit` out of the library for now.
  - Added app opt-in through `ALTIVECCOCOA_REQUIRED`,
    `ALTIVECCOCOA_LINKAGE`, and `ALTIVECCOCOA_DIR`.
  - Acceptance: Mac apps can opt in with `ALTIVECCOCOA_REQUIRED=1` and use the
    three-pane nibless controller stack without copying ENIL sources; iPhone
    apps can require the static library by default, with dynamic
    framework linkage available only as an explicit iOS 8+ opt-in.

- [x] **Font Awesome optional icon helper**
  - Source: `/repo/ENIL-cocoa/source/shared/FontAwesome.*`,
    `/repo/ENIL-cocoa/source/tools/gen_faicons.py`, and bundled OTF files.
  - Migrated as `AIFontAwesome` inside `AltivecCocoa`.
  - Renamed public symbols to the Altivec namespace (`AIFontAwesome`,
    `AIFontAwesomeIcon`, `AIFontAwesomeStyle`, `AIFA...` enum values).
  - Kept generated Solid icon enum regeneration through
    `libs/cocoa/tools/gen_aifontawesome_icons.py`.
  - Preserved Core Text rendering on 10.5+/iOS and ATSUI fallback on Tiger.
  - Static linkage stages OTF files into the app bundle; dynamic linkage keeps
    OTF files inside `AltivecCocoa.framework`.
  - Bundles a Font Awesome Free / SIL OFL 1.1 notice alongside the OTF files.
  - Acceptance: apps can render Font Awesome icons through AltivecCocoa without
    copying ENIL helper code or writing custom font staging rules.

- [ ] **C utility extraction candidates**
  - Source: `/repo/ENIL-cocoa/source/shared/enil_strbuf.*` and the pure-C
    headers around `enil_cocoa.m`.
  - Possible reusable pieces:
    - growable string buffer.
    - HTML, JS, and URL escaping helpers.
    - Apple-framework bridge pattern that keeps portable `.c` files free of
      Foundation/AppKit/UIKit imports.
    - ImageIO JPEG thumbnail/transcode helper.
    - CFDateFormatter timestamp helper.
    - CFStringCompare SQLite collation helper.
    - C-to-NSLog bridge.
  - These are lower priority because they need naming cleanup and careful API
    boundaries.
  - Acceptance: only extract pieces that remove real duplication in Altivec
    examples or libraries.

- [ ] **Release helper**
  - Source: `/repo/ENIL-cocoa/scripts/version-bump-push.py` and `RELEASE.md`.
  - Generalize the workflow for apps with paired macOS/iOS `Info.plist` files:
    version check, patch bump, commit, tag, and optional push.
  - Keep this secondary; it is project workflow, not core build capability.
  - Acceptance: a template app can opt into shared release versioning without
    adopting ENIL-specific paths or names.

## Do Not Migrate

- LINE protocol, sync, database schema, QR login, and SSE engine code.
- ENIL UI controllers, message rendering, sticker-specific behavior, and CSS,
  except as reference material.
- ENIL notification names, account/session paths, worker credentials, or
  product text.

## Cleanup Targets In ENIL After Migration

- Point ENIL at `/altivec/libs/sqlite/build-{mac,phone}` instead of local
  SQLite outputs.
- Remove ignored SQLite generated outputs from `/repo/ENIL-cocoa` after the
  Altivec SQLite library is available.
- Replace local iOS order-only bundle/signing rules with common Altivec hooks.
- Replace copied compatibility files with Altivec-provided headers/sources or
  documented template includes.
