# Shared SQLite and list infrastructure

Opt in per product, using a toolchain image built from this revision:

```make
MyApp_CORE = static
MyApp_COCOA = static
MyApp_SQLITE = 1
```

`MyApp_SQLITE` adds the independent static `AltivecCocoaSQLite` archive and
headers. CORE must be explicit. C-only consumers may omit COCOA; Objective-C
consumers link Foundation. Basic AltivecCocoa users acquire no SQLite dependency.
Mac frameworks may consume the SQLite static archive alongside dynamic CORE.
The optional archive ships separately for Mac and iOS in release assets.

Build with `make -C libs/cocoa-sqlite all` after installing the SDKs and building
AltivecCore. Its C sources can also be compiled directly by Linux harnesses with
system SQLite and pthreads. The bundled SQLite headers define the production
API/version; the library uses no row-value SQL or assumed application schema.

## Change delivery

`ai_store_feed` owns an immutable store identity and a bounded, thread-safe
revision journal. Numeric IDs and copied UTF-8 application/composite IDs are
supported. Topics are app-defined bit masks; scopes identify accounts or domain
containers. Missing scope/record detail, reset, journal overflow, output-buffer
overflow, and oversized keys request a full resync. Events invalidate reads;
they are not a row audit log or a replication protocol.

Capture `next` **before** the authoritative read. Apply the result successfully,
then advance that observer's cursor to `next`. Another window owns another
cursor. A write during the read stays beyond `next` and is picked up next time.
A daemon adapter must report reconnect/lost coverage as a full invalidation;
SQLite hooks do not deliver cross-process events. Strappy keeps its existing IPC
handshake and reconnect logic and now delegates its journal to this library.

`ai_store_writer` opens and owns a connection, so installing its optional update
hook cannot replace a previous hook owner. Serialize access and use its explicit
begin/savepoint/rollback-to/release/commit operations; do not execute transaction
control SQL or replace hooks behind it. Savepoints are LIFO, library named.
Record domain candidates with `ai_store_writer_change[_key]`. Successful COMMIT
publishes them; failed/rolled-back work never publishes. After a transaction
error, roll back before beginning another transaction. Hooks only mark a dirty
hint, without SQL or Cocoa callbacks. Hook-derived changes always request a
full reread; exact reporting requires explicit domain candidates with hooks off.

For existing app-managed transactions, `ai_store_feed_publish` is the explicit
post-commit boundary. The caller must verify commit success first. Hook omissions
include WITHOUT ROWID and some REPLACE/delete operations; an absent hook event
is not proof of no change. See SQLite's [update hook](https://www.sqlite.org/c3ref/update_hook.html)
and [commit hook](https://www.sqlite.org/c3ref/commit_hook.html) contracts.

`AIStoreObserver` copies/coalesces topic/scope hints and delivers on the main
thread. The payload includes store identity and lifecycle generation. Numeric
scope mappings remain app-owned; record details come from the C feed/read.
The target is borrowed: invalidate on the main thread before destroying it.
Set a new generation when changing accounts/filters; producers with the old
generation are ignored. Queued callbacks after invalidation do nothing.

## Snapshots and rows

`ai_query_snapshot` opens a read-only connection and pins one committed view
before any count/section/page queries. It caches at most eight prepared
statements; checkouts must be returned to reset bindings. Callers serialize the
connection and supply parameterized SQL, stable ordering and matching indexes.
It performs no migration, write, schema mapping or ORM work. Cancellation calls
SQLite's interrupt API; close only after the reader finishes. Closing releases
its WAL snapshot. Long-lived readers retain WAL history, so replace/release
obsolete views promptly. Apps needing materialized temp-table snapshots can
keep their existing source implementation (as Strappy does).

`AIPagedRows` in **AltivecCocoa** is schema-independent. Subclasses supply a count
and 32-row `pageAtOffset:error:` implementation. It keeps four pages (128 rows),
reuses sequential pages, and permits arbitrary index access. A nil/short page
inconsistent with the count is an error, not empty data. `objectAtIndex:` is the
synchronous compatibility/bulk API. Apps that opt into placeholder rendering use
`requestObjectAtIndex:placeholder:` and observe `AIPagedRowsDidLoadNotification`.
Missing pages run on a serialized worker, with four pending requests and at most
one pending main-thread delivery. `invalidatePages` discards queued requests and
stale results. Build expensive source counts/sections on a worker before
publishing the source. Filters should produce replacement snapshots rather than
mutating one still displayed. Identity/selection and editing policy stay with
the table's app adapter.

Strappy's model tables use asynchronous page requests; its model and database
catalog rows both use the shared cache. Retro-DLP uses bounded database pages
to prepare complete presentation snapshots before exposing rows to AppKit/UIKit.
Its first load is synchronous and retains all display text; cell callbacks do
not request pages or show placeholders. Appearance does not reload content.
Actual changes and explicit refreshes prepare replacements on a coalescing
background loader while old rows remain visible. Obsolete requests are cancelled
and selection/scroll anchors are restored by identity. Explicit domain actions
recheck records/files through synchronous APIs; UI readers are separate from writes.

Retro-DLP's lifecycle, eager presentation policy, indexes, section queries and
representative-download policy remain app-owned. The shared collection adapters
support both ready snapshots and opt-in placeholder paging. Full query-plan,
WAL, memory and scrolling benchmarks remain separate from the native regressions.

`AICoalescedCallback` is a main-thread idle/max-wait debounce with a borrowed
target and explicit invalidation. ENIL uses it for committed SSE UI batches,
retaining its ordered domain events and JavaScript construction. rCloud's
Contacts/Calendar publication and durable recovery journals are different
contracts and were not replaced with UI invalidation machinery.

## Compatibility and verification

| Surface | Deployment floor | Ownership/fallback |
| --- | --- | --- |
| Portable C | pthreads + bundled SQLite | Explicit connection/feed lifetime; errors are SQLite codes |
| Cocoa adapters | macOS 10.4 PPC/i386; 10.9 x86_64; 11 arm64 | MRC, selectors and locks; no blocks/ARC requirement |
| iOS adapters | iOS 5 armv7 / iOS 7 arm64 | Static archives; main-thread notifications |
| Table updates | Same legacy floors | Coalesced reload for loaded pages; app identity mapping on replacement |

Strappy/ENIL's older documentation mentions iOS 4.3, but their current Make
builds use Altivec's iOS 5 floor. This module does not add an iOS 4.3 claim.

Portable regressions: `make -C libs/cocoa-sqlite test`. They cover transaction
rollback, savepoints, failed commit hooks, deferred constraint failure,
WITHOUT ROWID explicit reporting, numeric/text identities, independent cursors,
reconnect/overflow, snapshot isolation, statement reuse and WAL release. A
100,000-row fixture reports CPU time, query count and retained WAL size; these
are measurements, not a legacy-device performance budget.

Native regressions: `make -C libs/cocoa-sqlite/tests release` (Mac), or add
`TEST_PLATFORM=iOS`. Run the resulting `SQLiteFoundationTest` in a caller-owned
test directory. It checks 100,000-row random access, cache bounds, async loading,
obsolete generations, observer invalidation and debounce disposal. Existing
consumer suites remain required; cross-compilation alone is not native coverage.

The first migration was validated with Linux suites for this library, Strappy,
Retro-DLP, ENIL and rCloud; address/undefined-behavior sanitizers for the new C
layer and Retro-DLP's C ownership tests; and all library architecture slices.
The Foundation harness passed on x4-vm (Tiger PowerPC) and koolphone5 (iOS 8
armv7). On that phone, sign the copied harness with the device's `ldid -S`
before running it. Retro-DLP's offline AppKit regression suite also passed on
x4-vm. Consumer native builds and package checks passed; existing Cocoa and
vendor compiler warnings remain. No published image/tag/release is implied by
local builds or commits.
