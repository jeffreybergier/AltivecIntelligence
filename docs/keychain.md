# Shared Keychain storage

`AIKeychainStore` is an optional-use Foundation service in AltivecCocoa. It
requires no AltivecCore, initialization at app launch, network, ARC, blocks,
properties, or modern Objective-C syntax. Merely linking AltivecCocoa performs
no Keychain operations. Both static libraries include it; the Mac framework
exports it. The shared Make fragments link Security.framework for static users.

## API decision

We compared the public headers of
[SAMKeychain (formerly SSKeychain)](https://github.com/soffes/SAMKeychain/blob/master/Sources/SAMKeychain.h),
[SAMKeychainQuery](https://github.com/soffes/SAMKeychain/blob/master/Sources/SAMKeychainQuery.h),
and
[UICKeyChainStore](https://github.com/kishikawakatsumi/UICKeyChainStore/blob/master/Lib/UICKeyChainStore/UICKeyChainStore.h)
on 2026-10-15.

| Candidate | Useful shape | Fit for our apps |
| --- | --- | --- |
| SAMKeychain | Class conveniences keyed by service/account; a mutable query object with fetch/save/delete, password data, account enumeration, and NSError results | Compact for generic passwords. The published query has no equivalent server/path/port/internet-password scope, so it would need a separate API for ENIL and Strappy's existing internet credentials. Global accessibility defaults also complicate consumers with different policies. |
| UICKeyChainStore | An instance scoped to a service or internet server, with string/data methods keyed by account; access group and accessibility configuration | Better match for both credential classes and per-consumer configuration. Its full surface includes many conveniences and newer features that our consumers do not need. |

Chosen: a small **UICKeyChainStore-style instance API**, with a new AI-prefixed
class and an independent MRC implementation. No third-party implementation,
dependency, or license text was copied. This is not a drop-in replacement.

Retained concepts: service/server scope, string/data storage, explicit deletion,
account enumeration, access groups, creation accessibility, and NSError results.
We omit general class-method overloads, global default service, subscripting, serialized
objects, bulk deletion, synchronization, biometrics and shared web credentials.
Missing reads/deletes return the native not-found error; nil writes are invalid.
This keeps missing credentials distinct from denied access and decode failures.

## Usage

```objectivec
AIKeychainStore *store = [[[AIKeychainStore alloc]
    initWithService:@"com.example.myapp.token"] autorelease];
NSError *error = nil;
BOOL saved = [store setString:token forKey:account error:&error];
NSString *loaded = [store stringForKey:account error:&error];
// Inspect saved/error as appropriate; never log the token.
```

Use `dataForKey:error:` and `setData:forKey:error:` for arbitrary bytes. Empty
values and embedded NULs are preserved. Invalid UTF-8 through the string getter
returns `AIKeychainErrorDecode`. Errors use `NSOSStatusErrorDomain`, carry native
OSStatus codes and include no credential identity or value. Success clears the
error output. The header exposes names for three native status values absent
from the old SDK's Security headers.

Internet stores take an NSURL, explicit HTTP/HTTPS protocol and authentication
type, and security domain. Account, server, explicit port (or zero), path,
security domain and authentication all participate in matching. Normal operations do not infer a default port or rename secrets.
A separately named legacy discovery method supports existing account-only app
schemas; normal store operations always use the exact scope. The URL's
user/password/query/fragment are ignored. A nil security domain means
an exact empty domain. Use `Default` authentication for new cross-platform
items. `Unspecified` preserves the old Mac zero attribute; iOS rejects it with
invalid-argument instead of substituting another identity.

## Platform and ownership contract

| Area | Mac | iOS |
| --- | --- | --- |
| Backend | SecKeychain search/create/read/modify/delete, including modern Mac slices | SecItem query/update/add/delete |
| Build floors | PPC/i386 10.4, x86_64 10.9, arm64 11.0 | armv7 5.0, arm64 7.0 |
| Scope | Default native search list, or an explicitly retained SecKeychainRef | Entitlement-selected default group or explicit access group |
| Creation policy | Optional retained SecAccessRef for trusted-application ACLs | System default, WhenUnlocked or AfterFirstUnlock, with device-only variants |
| Existing item update | Preserves identity and ACL by default; explicit policy-update opt-in | Preserves identity and accessibility by default; explicit policy-update opt-in |
| Background interaction | Explicit process-wide disable method; call at daemon startup before threads | No new no-dialog guarantee for externally created authentication-protected items on legacy iOS |

`setUpdatesAccessPolicy:YES` is an explicit opt-in for rCloud's Save behavior:
it applies the configured Mac ACL or iOS accessibility to existing items too.
On failure, the native error is returned before changing the password. A label
can be configured for new entries without changing their lookup identity.

Mac rejects non-nil access groups and non-default iOS accessibility options.
iOS validates the enum and group before doing native work. Unsupported options
never silently succeed. The API does not grant entitlements or bypass Keychain
permissions. Mac defaults remain the file-based Keychain even on modern hosts.

Stores own copied scope strings. Native Mac Keychain/access references are
retained until replaced or deallocation. Calls are synchronous; configure stores
before sharing and serialize their use. An operation can block on native access
checks; schedule it in the app's existing worker as appropriate. The library
never temporarily changes the process-wide interaction setting around a call.

Writes update first (Mac searches first), create only when missing, and retry an
update once if creation races another writer and reports duplicate-item. They
never delete as part of saving. Native failures propagate without unbounded
retries. The API does not claim transactionality across processes.

`allKeysWithError:` reads account metadata only, sorts the result, returns an
empty array for an empty scope and nil for failures. It does not read passwords.
No library-level secret cache exists. Foundation values use ordinary MRC memory;
this wrapper does not promise zeroization of released buffers.

## Consumer migration boundaries

ENIL and Strappy retain their XPKeychain facades as small policy adapters.
Their repeated native backends are removed. The shared
`internetPasswordStoreForKey:error:` bridge discovers the first legacy
account-only internet entry without reading its password, then returns an exact
scoped store retaining its native keychain/access group. Unknown protocols or
authentication types fail rather than being reinterpreted. The optional Mac
`inKeychain:` overload supports isolated tests. `serverURLString` reconstructs
the legacy display URL. Newly saved internet entries retain the apps' original
Mac zero/iOS default authentication conventions.

Same-scope password edits update in place. Changing URL retains the apps'
existing delete-and-replace policy; it is not atomic and a failed new save may
leave the old entry removed. Mac deletes the first account match; iOS removes
account matches in a bounded loop (128 attempts to stop concurrent recreate
races). Account naming, OAuth, serialization, environment overrides, caches and
notifications stay in the app facades. Strappy's daemon-wide no-dialog setting
and device-only generic-password creation policy are preserved.

rCloud keeps its C-facing functions, but their implementations are now MRC `.m`
adapters. Mac trusted-application ACL construction remains app-owned. The
shared store handles CRUD, metadata-only existence, creation labels and explicit
ACL refresh. The iOS adapter keeps its access group, 4096-byte limit and
AfterFirstUnlockThisDeviceOnly policy, including policy refresh on updates.

Retro-DLP was re-audited: its first-party source has no Keychain backend or
SecItem/SecKeychain calls to migrate. Its cookie-file behavior was not changed.

The `AIKeychainStorage` protocol permits app tests to inject an in-memory fake;
there is no implicit fallback to memory when native storage fails. A reusable
in-memory implementation is not shipped in this slice.

Physical source-line comparison (including comments/blank lines; formatting
is not normalized): the four original backend regions totaled 1,508 lines;
remaining app adapters total 468 lines, and the new shared implementation plus
public header total 763. Net reduction is 277 lines, excluding tests,
documentation and Make wiring. This is measured deletion, not the earlier
roadmap's projected 1,507-line saving.

## Validation

Run on a Mac:

```sh
bash libs/cocoa/tests/test_keychain.sh
```

The native test creates and deletes its own temporary Keychain, never the login
Keychain. It exercises missing/empty/binary/Unicode values, updates, deletion,
service and internet port separation, enumeration, unsupported policy errors,
locked-Keychain denial without UI, and compatibility with generic and internet
entries created by the old native API. The second test
executes the production iOS branch with a SecItem recorder, exercising exact
query fields, access groups, creation policy, failures and duplicate-add races.
It does not exercise an iOS security daemon or entitlements. CI runs both on Mac.

Inside the existing image with SDK volumes:

```sh
bash /altivec/libs/cocoa/tests/test_keychain_cross.sh
```

This compiles/links all six slices with warnings treated as errors and signs
the iOS native test executable. Set `KEYCHAIN_TEST_OUTPUT_DIR` to retain the
PPC/armv7/arm64 executables for explicit native deployment. The iOS fixture uses
a dedicated test access group and unique service/domain names, and removes
only its own entries. It needs a jailbreak-compatible signing environment.

Optional sibling-checkout integration tests:

```sh
bash libs/cocoa/tests/test_keychain_consumers.sh
KEYCHAIN_SIBLINGS=/siblings KEYCHAIN_TEST_OUTPUT_DIR=/output \
  bash /altivec/libs/cocoa/tests/test_keychain_consumers_cross.sh
```

These compile the real app facades and redirect default Keychain selection to
an isolated temporary Keychain. rCloud's existing-item ACL-edit call is recorded
so unattended tests can exercise success/denial propagation without a native
authorization prompt; the rest of its storage and new-item ACL creation are
native. Executables have a 30-second deadline. Actual existing-item ACL edits
are not established by these recorder assertions.

Validated locally on 2026-10-15:

- Host Mac native library tests, production iOS branch with SecItem recorder,
  and three consumer facade tests passed.
- `x4-vm` (Tiger 10.4.11/PPC) passed the native library test and all three
  consumer facade tests using disposable Keychains under `~/Desktop`.
- All six library compile/link checks passed. Full Mac static/framework and
  iOS static builds passed; header packaging and Mac class exports were inspected.
- Strappy, ENIL and rCloud clean Mac/iOS debug and release builds and their
  complete offline suites passed. Host Mac and armv7 Clang static analysis of
  the shared implementation reported no findings.
- Shared Make regression tests passed (17 run; Debian packaging skipped on the
  host because `dpkg-deb` is unavailable).
- `koolphone5` SSH timed out. Its signed native armv7 executable is prepared,
  but iPhone runtime coverage is explicitly skipped with user authorization.
- Native rCloud existing-item ACL editing timed out on the modern host and
  was denied in the noninteractive Tiger fixture. The bounded recorder test
  proves forwarding/failure behavior, not real ACL-edit authorization.

The full shared-library build reports an existing function-pointer cast warning
in `AIWebViewController.m:51` for modern Mac slices; Keychain checks pass
`-Werror`. App builds had no non-deprecation warnings. Real consumer login,
locked-iPhone behavior, provisioned access-group sharing, and interactive ACL
updates remain separate validation work. No existing user credentials or
installed apps were changed by these tests.
