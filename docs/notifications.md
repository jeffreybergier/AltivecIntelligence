# Shared local notifications

`AILocalNotificationCenter` is part of AltivecCocoa, with the same Foundation
header on Mac and iOS. It needs no AltivecCore, database, or network connection.
Rebuild the library/image before building migrated consumers; an older prebuilt
AltivecCocoa archive or framework does not export this class.

Initialize the center during application launch, before message/download events:

```objc
#import <AILocalNotificationCenter.h>

AILocalNotificationCenter *center = [AILocalNotificationCenter defaultCenter];
[center requestAuthorization];
[center postNotificationWithTitle:title body:body userInfo:routingPayload];
[center setBadgeCount:unreadCount];
```

All calls require the main thread. Apps own message wording, privacy, unread
counts, account selection, and navigation. The library observes application
lifecycle notifications, presents only in the background, resets the badge on
background entry, and clears alerts followed by the badge on activation,
including cold launch. iOS foreground entry suppresses alerts before the app
becomes active. Positive badge writes while foregrounded become zero.

The iOS backend preserves ENIL's `cancelAllLocalNotifications` followed by a
permission-aware badge reset. ENIL's delivered-tray clearing has been observed
by the user on their device; the cancellation call alone is not what establishes
that behavior. Each alert carries the current nonzero badge, or 1 when no unread
count exists, so Retro-DLP also gets a nonzero-to-zero transition. Badge-disabled
systems cannot use that mechanism. Scheduled cancellation and delivered-alert
removal remain different OS operations; this API intentionally clears app-wide
notification state. It is not suitable alongside an independent scheduler whose
pending alerts must survive foregrounding.

## Capability and compatibility

| Backend | Build SDK / floor | Permission and fallback |
| --- | --- | --- |
| Mac legacy AppKit | 10.5 SDK, Tiger PPC/i386 | No native notifications before 10.8: returns Unsupported; no fake success. Dock badges runtime-gated on 10.5+. |
| Mac AppKit notifications | 11.3 SDK, 10.9 x86_64 / 11 arm64 | Runtime `NSUserNotificationCenter`; authorization Unknown because this API cannot determine the user's settings. |
| iOS UIKit notifications | 8.4 SDK, iOS 5 armv7 / 7 arm64 | `UILocalNotification`; iOS 8 requests alert, sound, and badge permission explicitly. No prompt on older supported iOS. |

No blocks, ARC, newer framework linkage, entitlements, or signing changes are
required by the library. Existing app installation/signing requirements still
apply. Modern UserNotifications support is separate future work.

`AINotificationSubmitted` means handed to the native backend, not confirmation
that the OS displayed a banner. Foreground suppression, known denial,
unsupported systems, and submission failure have distinct results. On iOS 8,
empty notification settings cannot distinguish an unasked user from denial;
this returns Unknown and never prevents an explicit permission request.
Authorized means some notification types are enabled, not that every type is.

## Activation and lifetime

Set a borrowed `AILocalNotificationCenterDelegate` for app-owned navigation.
Mac activation is forwarded internally; the native center owns the legacy
system center's delegate, so apps must not replace it. iOS app delegates forward
`userInfo` through `activateWithUserInfo:` from the launch-options local
notification and from `didReceiveLocalNotification:` **only when inactive**.
Forward once per OS callback; foreground receipt is not user activation.
Configure the routing delegate before forwarding the cold-launch payload.
Payloads should be small property-list dictionaries and contain no secrets.

Use `initWithBackend:` for recording/failure-injection tests. The backend is
retained; the routing delegate and backend's center pointer are borrowed.
Invalidate a non-singleton center before tearing down its delegate. Invalidation
removes lifecycle observers, detaches native activation, and disables subsequent
requests. No workers or delayed callbacks are created by this module.

## Consumers and tests

ENIL uses the shared service on Mac and iOS and removes its private notification
wrappers, permission helpers, and lifecycle cleanup. Retro-DLP's iOS app keeps
its existing completion wording and domain event, while shared code handles
background suppression, badge permission, presentation, and foreground cleanup.
Retro-DLP's Mac app had no notification feature to migrate.

Strappy also uses the shared center on Mac and iOS, initialized at launch. It
retains session titles, the localized `Prompt completed.` / `Prompt failed.`
text, and background-only completion alerts before releasing its last iOS
background allowance. No session payload or new navigation behavior is added.
On iOS it still submits only when authorization is Authorized; Mac permits
Unknown because legacy AppKit cannot query permission. The shared iOS backend
reports empty settings as Unknown (the old wrapper reported Denied), so launch
explicitly requests authorization in that case. The OS controls whether a prompt
can appear. Authorization requests now include badge permission, and shared
foreground cleanup clears alerts and the badge; Strappy has no independent
notification scheduler to preserve.

Strappy's unsandboxed iOS system-app installation has a recorded limitation:
SpringBoard may accept a local alert without displaying it in BulletinBoard.
The shared API does not fix or detect that installation limitation, and
Submitted must never be presented as proof of display. Final `koolphone5`
permission/display/cleanup checks are tracked in [the active roadmap](TODO.md), separately from
the passing recording-backend tests and the separately documented Keychain
runtime checks.

From Strappy, build the offline production-delegate regressions with
`python3 source/daemon/tests/notifications_test.py macOS` (or `iOS`) inside the
container. The Mac executable runs directly without production app startup;
the iOS build uses an isolated sandboxed test identity and records PASS in
`Documents/notifications-result.txt`. Neither starts accounts or the daemon.
These tests cover completion wording, foreground/background behavior, permission
mapping, and foreground cleanup, but cannot validate production installation
or OS banner display.

Build the deterministic recording-backend harness:

```sh
make -C libs/cocoa/tests release
make -C libs/cocoa/tests release TEST_PLATFORM=iOS
```

The executable tests foreground suppression, background relaunch, cold-launch
activation, cleanup order, badges, authorization outcomes, Unicode/routing
payloads, submission errors, and invalidation. These require Foundation on a
native Apple runtime; Linux can cross-build them but cannot execute them.
Retro-DLP's existing offline iOS suite additionally tests the production app
delegate and scheduler with an injected recording backend. Build only that
scenario with `RDLP_TEST_NOTIFICATIONS_ONLY=1 python3
source/gui/iOS/tests/build_ios_ui_test.py` from Retro-DLP after `make app-iOS`.

Scheduling, stable request IDs/replacement, per-notification removal,
configurable foreground presentation, and modern notification backends remain
follow-on work. This first slice provides immediate alerts and ENIL's shared
lifecycle behavior.

Validation for this implementation (2026-10-12): the recording harness passed
on x4-vm (Mac OS X 10.4 PowerPC, static and dynamic linkage) and koolphone5
(iOS 8 armv7). Retro-DLP's offline iOS UI suite and the focused production
scheduler/delegate notification suite also passed on koolphone5. Library and
harness cross-builds passed for ppc, i386, x86_64, arm64 Mac and armv7/arm64 iOS.
ENIL clean debug/release builds, Linux host tests, and package validation passed;
Retro-DLP Mac/iOS builds, app regressions, and package validation passed. Existing
AIWebViewController cast and vendor C warnings remain; the new notification
sources build without warnings. These runs do not establish visual OS banner
presentation or notification-tray removal, which need separate device checks.
The existing image was overlaid with current sources for testing; no toolchain
image or release was published.

Strappy follow-through (2026-10-15): clean debug/release builds passed for all
four Mac slices and both iOS slices without compiler warnings. The isolated
production-delegate test cross-built for the same six slices and passed on the
host Mac and `x4-vm` (Tiger/PPC). Tiger additionally returned Unsupported from
the native backend. The shared notification regression harness passed on
`x4-vm`; Strappy's app-boundary check passed. The migration removes 286 lines of
private backend/declaration/helper code; app integration adds 22 net lines,
for a net reduction of 264 production source/header lines. No shared library
implementation was added; test and documentation lines are excluded. Phone
runtime, production installation/display, and permission combinations were not
tested, per the user's deferral. No image or release was published.

Phone follow-through (2026-10-15): Strappy's isolated production-delegate IPA
and the shared notification harness both passed on `koolphone5`, iOS 8.4.1
(12H321), armv7. The test IPA now registers `strappy-notifications-test://` for
launch through this phone's URL-only `uiopen`; the result was retrieved from
its isolated sandbox. The standalone shared harness required on-device ad-hoc
signing with `ldid -S` before execution. No production app, accounts or daemon
were started by these tests. Actual production banners, notification-tray
removal, and native permission combinations remain unverified; the iOS tests
exercise recording-backend policy/lifecycle behavior, not visual OS display.
The separate native Keychain phone tests subsequently passed; see
[keychain validation](keychain.md).
