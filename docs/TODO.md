# Active roadmap

Remaining work extracted from the improvement plan on 2026-10-15. Completed
implementation records and earlier audits are in [history.md](history.md).
This reorganization does not establish new build or native-test evidence.
Paths in backticks are repository-relative unless explicitly described otherwise.

## Priority

1. Audit consumer SQLite queries and add regressions for ordering, NULLs,
   deletes, and query plans. Keep the existing SQLite/observation infrastructure.
2. Close native collection/UI gaps and measure end-to-end legacy-device behavior.
3. Finish interactive Keychain and visible notification validation.
4. Evaluate narrow Mac launchd helpers only if two consumers demonstrate a
   meaningful net reduction in maintained code.
5. Defer broader background, service, test-support, and asset-cache frameworks
   until an app need and a successful pilot justify them.

## Delivery rules

Keep operational validation separate from optional library expansion. Preserve
existing consumers through compatibility entry points or coordinated migrations.
New modules need two real consumers, a license audit, measured implementation
and adapter costs, documented fallbacks, and applicable portable/cross-build/
native checks. Apps retain business policy. Image rebuilds, device installation,
and publication are separate work, not implied by a documentation review.

Current contracts: [Keychain](keychain.md), [notifications](notifications.md),
[SQLite](sqlite.md), and [collections](../libs/cocoa/COLLECTIONS.md).

## Artwork and packaging that survive old devices

- [ ] Extend native icon/launch evidence to iOS 5 and Leopard; those OS versions
  were not available on the supplied test machines. See
  [template coverage](app-templates.md).

## Examples and documentation

- [ ] Keep tiny sample apps as build fixtures; make richer examples generated
  from supported templates so documentation and templates cannot drift apart.
  Replace duplicated CURL-wrapper teaching examples with a minimal direct-libcurl
  or shared-model example matching the current development guidance.

## Extraction evidence

- [ ] For each proposed extraction, record app implementation lines removed,
  shared implementation lines added, and remaining adapter/configuration lines
  using comparable formatting; report tests separately. Require substantial
  repeated mechanics removed across at least two real consumers. Moving unique
  app code into a library, or adding an unused general framework, does not pass.

## Library boundaries and compatibility contract

- [ ] Extend capability documentation when new backends or signing profiles land;
  do not infer native coverage from cross-builds.

- [ ] Apply the same ownership/shutdown contract to future background and service
  adapters, including nonblocking teardown and expiration races.

## Keychain validation and optional test support

- [ ] Add a reusable in-memory store for offline app tests if needed. The shared
  `AIKeychainStorage` injection protocol and deterministic native-call recorders
  are implemented; no reusable in-memory backend is shipped yet.

- [ ] Complete remaining Keychain native coverage: interactive Mac ACL edits,
  real consumer login, locked-iPhone behavior, provisioned access-group sharing,
  and other supported OS/architecture combinations. Isolated fixture results
  do not establish these scenarios.

## Local notifications and notification activation

- [ ] Check production permission settings, background success/failure banners,
  foreground suppression and visible alert/badge cleanup on `koolphone5`.
  Record the unsandboxed/system-app display limitation separately from successful
  submission; the passing recording tests cannot prove banner/tray display.

- [ ] Verify actual notification-tray clearing and permission combinations across
  supported iOS versions. ENIL has a user-observed clearing result, but recording
  tests and that observation do not establish the full OS/permission matrix.

- [ ] Add scheduling, stable request IDs, replacement/per-notification removal,
  and configurable presentation policies, with cancellation and duplicate/racing
  completion regressions for those new APIs. Keep wording/privacy/routing in apps.

- [ ] Evaluate a modern UserNotifications backend against the provisioned SDKs;
  add an explicit app/delegate presentation fallback where native alerts are
  unsupported. The current backend reports Unsupported without fake success.

## Committed SQLite changes from C to Objective-C

- [ ] Complete app-level native evidence for two independent windows across daemon
  restart/reconnect and account teardown with callbacks in flight. Portable
  cursor/reset tests do not by themselves establish those full UI/IPC scenarios.

## Collection correctness and performance

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

## Background work, progress, and service lifecycle

- [ ] After a deletion-positive finite-task pilot, consider
  `AIBackgroundWorkCoordinator` with explicit work tokens, operation
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

- [ ] First evaluate the repeated Mac launchd helpers identified in the
  [historical audit](history.md). Pilot
  broader `AIServiceClient` status/control adapters only after demonstrating
  matching removable transport/lifecycle code in Strappy and rCloud:
  readiness, timeout, reconnect, stop acknowledgement, and bounded log tails.
  Keep service installation and privilege decisions in the existing package
  tooling. Test with isolated fake services and restart/failure injection.

## Entitlements, signatures, and capability diagnostics

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

## Offline native UI test support

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
  existing native runners and [deployment recipes](deployment.md); avoid
  hard-coded personal devices or a new deployment framework.

- [ ] Share scenarios for empty/error/loading lists, burst refreshes, selection
  preservation, notification activation, expiration/completion races, service
  reconnection, and window/controller teardown. Report tested OS/architecture
  and skipped native coverage separately from portable or cross-build results.

## Follow-on candidates and delivery gates

- [ ] Evaluate bounded asset loading/caching using ENIL's `enil_asset_cache` and
  Retro-DLP's thumbnail consumers: cancellation on row reuse, deduplicated
  requests, byte limits, atomic cache writes, and main-thread publication.
  Extract only after a second consumer validates the same contract.

- [ ] Continue with background/service adapters and capability profiles, adding
  offline regression support with each slice.

- [ ] For future modules, validate a pilot and second independent consumer,
  audit source licenses, and record removed wrappers/remaining app configuration.
  Add optional shared-module examples to `cocoa-shared`/`cocoa-daemon`; the basic
  generated templates do not yet teach all of the new capabilities.

