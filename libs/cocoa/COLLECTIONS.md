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

The result selector runs on the main thread. A thrown builder exception becomes
a result dictionary containing an NSError under `error`; domain-specific
builders should return their own errors. Neither a controller nor a table
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

In the main-thread result callback, **replace the app's table data-source model
first**, then call `[adapter applySnapshot:snapshot]`. The adapter does not
replace the data source or delegate. The snapshot must describe exactly the
section/row counts that the data source now reports. AppKit concatenates section
rows; any group/header rows must be represented by the app itself.

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
- Diff metadata is capped at 4,096 rows and 4,096 sections. More than 512 edits,
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
| rCloud | Status, Mail, Sync, choices and log | No native table or outline screens |

`AICollectionTableViewController` is an optional UIKit owner for small forms.
Override `collectionIdentifiersForSection:` with domain IDs, or use
`collectionFixedIdentifiersForSection:` only for fixed row roles. Change the
model before `refreshCollection`. Its adapter is owned and invalidated by the
base controller. Count-only snapshots can omit `rows` and provide `count`;
there is no placeholder payload allocation. Active form cells are excluded
from deferred content refresh while a descendant is first responder.

`AICollectionOutlineAdapter` handles two-level AppKit outlines: section IDs
are root items and row IDs are child items. It preserves expansion, selection
and the visible anchor. Supported runtimes apply child insertions/removals;
root changes and Tiger structural updates reload safely. Content-only page
updates refresh visible items without rebuilding the tree.

Strappy conversations, database catalogs and model preferences use the shared
refresh scheduler. Their readers project bounded IDs from the same SQLite
snapshot, without materializing display rows. Retro-DLP supplies identity-only
projections for playlist, entry and job queries, including grouped download
wrappers. rCloud's bounded log read runs on the shared worker. Existing
app-specific domain queries, rendering and command handling remain in apps;
this rollout does not make every pre-existing synchronous query asynchronous.
Duplicate identities (including repeated log lines), large lists and other
ambiguous snapshots retain the documented safe reload fallback.

## Validation

`tests/collection_test.m` covers randomized diff reconstruction, metadata bounds,
latest-request delivery, cancellation, teardown, and real NSTableView/NSOutlineView selection and expansion.
Retro-DLP's `ios_collection_test.h` exercises real UITableView row/section
batches, selection restoration, page updates, form insertion, and active-field
preservation in its isolated offline app.
Strappy's model-list C harness verifies bounded ID projection order and that
collecting IDs does not fetch display payloads.

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
