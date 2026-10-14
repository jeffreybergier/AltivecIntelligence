# Shared collection controllers

`AICollectionController`, `AICollectionSnapshot`, and
`AICollectionTableAdapter` expose the same API on iOS and macOS. They work with
plain arrays or `AIPagedRows`; they have no SQLite dependency. Apps retain their
queries, filters, sorting, sections, cell rendering, and editing behavior.

## Loading and ownership

Create one controller per list owner with `initWithTarget:selector:builder:`.
The builder implements `+buildList:` and receives an immutable request dictionary.
`request:` coalesces requests within a main run-loop turn. One serialized worker
keeps only the latest pending request. A generation check suppresses obsolete
results, including a result already waiting for main-thread delivery. Use
`cancel` immediately when a filter changes, even if launching the replacement
query is debounced. Builders can check `[[AICollectionController
currentController] isCancelled]` or connect that to their database progress
handler. Cancellation is cooperative; it never joins a worker on the UI thread.

`buildResultForRequest:` runs the same builder synchronously on the calling
thread, for consumers that prepare the initial source before presentation.
Later `request:` calls use the worker. Builders used through both entry points
must support both paths. The synchronous entry point returns directly; it does
not invoke the result selector or catch builder exceptions.

The result selector for `request:` runs on the main thread. A thrown worker
builder exception becomes a result dictionary containing an NSError under
`error`; domain-specific builders should return their own errors. Neither a controller nor a table
adapter retains its target/table. Call `invalidate` before destroying that
owner. The adapter removes its page observers and delayed work. The app must
invalidate its old paged sources and release its own snapshot references.

## Describing and applying a snapshot

Build `AICollectionSnapshot` on the worker from section dictionaries:

```objc
NSDictionary *section = [NSDictionary dictionaryWithObjectsAndKeys:
    @"models", @"id", rows, @"rows", identifiers, @"identifiers", nil];
AICollectionSnapshot *snapshot = [[[AICollectionSnapshot alloc]
    initWithSections:[NSArray arrayWithObject:section]] autorelease];
```

Section IDs must be unique. Row IDs must be unique within their section and
stable across reads; sort positions and display names generally aren't IDs.
Identity keys must be immutable and copyable. Snapshot construction copies
metadata and retains row sources; it never reads row payloads. `offset`/`count`
can describe a section's range within a shared row source. A wrapper may supply
`pageSource`/`pageOffset` to identify the underlying AIPagedRows publisher.

Receive results on the main thread and prepare their diffs **before replacing
the app's data-source model**:

```objc
- (void)rowsLoaded:(NSDictionary *)result;
{
  if ([loader prepareResult:result snapshotKey:@"collection"
      previousSnapshot:[adapter snapshot]]) return;
  // Publish the result's model here, then commit the table update synchronously.
  [adapter applySnapshot:[result objectForKey:@"collection"]];
}
```

`prepareResult:` returns YES while comparison is pending. The controller sends
only snapshot comparison to its existing serialized worker, then redelivers the
result to the same main-thread selector. The second call returns NO when the
prepared diff matches the adapter's exact previous snapshot. If that baseline
changed, it prepares again. Requests/cancellation/invalidation supersede pending
comparisons and deliveries using the same generation checks as list loading.
Use `prepareResult:previousSnapshots:` for a result with multiple snapshot keys,
as in Retro-DLP's Mac list/queue/outline update.

Initial snapshots with no previous model need no comparison. They publish and
reload immediately. The displayed model remains intact during later comparison;
model publication and table application happen together on the main thread,
without yielding between them. Do not pump the run loop or wait for a worker.
Selection and scroll state are captured at application time on the main thread.
The adapter does not replace the data source or delegate; AppKit concatenates
section rows, so app-owned header rows must be represented in the snapshot.

`applySnapshot:` never computes a diff. It consumes prepared changes only when
the previous snapshot identity matches; otherwise it safely reloads. Immediate
form mutations and `applyRowCount:` retain this synchronous fallback. Use the
preparation API for incremental lists. Diff caches retain an opaque previous
identity token, not the previous snapshot or its database row sources.

## Incremental updates and limits

- UIKit uses section and row insertion/deletion batches. Reorders become
  delete/insert pairs. Existing visible rows refresh after the structural batch.
- AppKit uses row insertion/removal batches on systems providing those APIs
  (10.7+). Tiger uses a full reload for structural changes.
- Page arrivals coalesce and refresh only affected visible rows. AppKit uses
  `reloadDataForRowIndexes:columnIndexes:` where available; Tiger invalidates
  affected cell-row rectangles. Page arrivals never cause a full list reload.
- Complete snapshots preserve selected IDs and the top visible row's offset.
  Identity is section-scoped; moving an item between sections is a new identity.
- Worker diff metadata is capped at 4,096 rows and 4,096 sections. More than 512 edits,
  missing/duplicate IDs, changed section titles, or inconsistent old table counts
  request a full reload. Apps can resolve selected/anchor IDs on their query
  worker for large-list fallback. These are safety bounds, not measured optimal
  performance thresholds. No table callback scans the entire database.
- Read failures from a current page source post
  `AICollectionReadFailedNotification` with the adapter as object. Apps decide
  how to present errors and retain unsaved edits separately.

## Native table rollout

Every shipping native table in ENIL, Strappy-Cocoa, Retro-DLP and
Retro-Cloud-Sync now applies updates through a collection adapter. Web-based
message/sticker views and text views are not native tables.

| App | iOS | macOS |
| --- | --- | --- |
| ENIL | Chats/friends/account, preferences, login client and QR/PIN/recovery tables | Chats/friends/account, About key/value tables |
| Strappy | Conversations, preferences, accounts/provider picker, providers/manual models/model editor, model and database whitelists, database study, session options, system prompts | Conversations, model/database/database-study preferences, accounts/provider chooser, provider/model editor |
| Retro-DLP | Library list controller hierarchy and settings | Library/downloads, queue, playlist outline sidebar |
| rCloud | Status, Mail, Sync and choices | No native table or outline screens |

`AICollectionTableViewController` is an optional UIKit owner for small forms.
Override `collectionIdentifiersForSection:` with domain IDs, or use
`collectionFixedIdentifiersForSection:` only for fixed row roles. Change the
model before explicitly calling `refreshCollection`, including initial setup.
Appearance callbacks never refresh the table. A full reload does not schedule
a redundant deferred content refresh. Its adapter is owned and invalidated by the
base controller. Count-only snapshots can omit `rows` and provide `count`;
there is no placeholder payload allocation. Active form cells are excluded
from deferred content refresh while a descendant is first responder.

`AICollectionOutlineAdapter` handles two-level AppKit outlines: section IDs
are root items and row IDs are child items. It preserves expansion, selection
and the visible anchor. Supported runtimes apply child insertions/removals;
root changes and Tiger structural updates reload safely. Content-only page
updates refresh visible items without rebuilding the tree.

Consumer inventory reviewed on 2026-10-14 against the 2026-10-13 follow-up
commits. Initial sources are prepared before presentation; data changes and
explicit refreshes request replacements while existing content stays visible.
Strappy conversations, database catalogs and model preferences use the shared
refresh scheduler. Their readers project bounded IDs from the same SQLite
snapshot, without materializing display rows. Retro-DLP supplies identity-only
projections for playlist, entry and job queries, including grouped download
wrappers. ENIL's chats/contacts use bounded SQLite roster pages. Retro-DLP,
Strappy and ENIL resolve cell text synchronously from bounded pages; the shared
placeholder API remains optional. rCloud's log is now `RCLogViewController`, a
scrolling text view, rather than a collection table. It reads a bounded 1 MiB
tail synchronously on initial load and uses the shared worker for subsequent
refreshes, preserving text selection and scroll position when possible.
App-specific domain queries, rendering and command handling remain in apps.
Duplicate identities, large lists and other ambiguous snapshots retain the
documented safe reload fallback.

## Validation

`tests/collection_test.m` covers worker-only comparison, main-thread receipt/
publication, superseding requests, baseline changes, exceptions, teardown,
unprepared/mismatched fallback, randomized diff reconstruction, metadata bounds,
latest-request delivery, cancellation, teardown, and real NSTableView/NSOutlineView selection and expansion.
Retro-DLP's `ios_collection_test.h` exercises real UITableView row/section
batches, selection restoration, page updates, form insertion, and active-field
preservation in its isolated offline app.
Strappy's model-list C harness verifies bounded ID projection order and that
collecting IDs does not fetch display payloads.

The following records the earlier rollout validation; the 2026-10-14 source/
commit review did not rerun native suites or establish coverage for every later
consumer fix.

Rollout validation on 2026-10-12: shared libraries built for Mac
ppc/i386/x86_64/arm64 and iPhone armv7/arm64; collection tests passed on the
host Mac and x4-vm (Tiger). Retro-DLP's full isolated AppKit suite passed on
x4-vm, including outline groups, queue selection and lifecycle. Retro-DLP's
full isolated UIKit suite passed on koolphone5, including native row/section
batches, active form fields, explicit Reveal selection, and unchanged-snapshot
scroll preservation for short inset tables. All four
apps' affected platforms cross-built; Strappy and ENIL used clean builds.
Strappy's offline Linux suite, Retro-DLP's store/service suite, ENIL's host
suite, and Strappy/Retro-DLP package checks passed. rCloud's isolated UIKit
harness built, but its native runner timed out without a report; retry on an
accessible phone. Strappy's optional GNUstep Foundation harness remains
unavailable in this container. The shared Mac build retains the existing
AIWebViewController function-pointer cast warning; no new collection or
consumer warnings remain.

The identity map uses nested section/row dictionaries, avoiding composite-array
hash collisions. See [snapshot benchmarks](tests/BENCHMARKS.md) for measured
construction/diff costs on the host Mac and x4-vm, remaining main-thread limits,
and reproduction commands.

Worker-diff validation (2026-10-14): the shared regression harness passed on
this Mac and x4-vm (Tiger PowerPC), including worker-thread comparison,
main-thread delivery, superseding requests, baseline replacement, comparison
errors, teardown, and native table/outline updates. Libraries and harnesses
cross-built for Mac ppc/i386/x86_64/arm64 and iOS armv7/arm64. ENIL and Strappy
clean debug/release builds and package checks passed; rCloud's unchanged iOS
settings callers also built. Retro-DLP's clean app builds, package checks, and
Mac/iOS UI harness builds passed; its full offline AppKit suite passed on Tiger,
including selection, queue updates, sidebar outlines, and lifecycle behavior.
The iOS test phone was unreachable, so the updated
UIKit regression is cross-build evidence only. The existing WebView cast and
Retro-DLP vendor warnings remain; the changed code has no new warnings.
Rebuild the shared library and migrated apps together; older image libraries
do not provide the preparation API. No image or release publication is implied.
