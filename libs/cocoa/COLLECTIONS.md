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

## Initial consumers and validation

Strappy's model preferences use the shared loader and adapters on both platforms.
Their SQLite bridge supplies a bounded identity-only projection from the same
read snapshot. Retro-DLP uses the loader on both platforms; its iOS library
lists use the adapter. Playlist metadata supports structural diffs; other
Retro-DLP query types retain structural fallback until they expose an ID-only
projection. All those iOS lists benefit from targeted page updates.

`tests/collection_test.m` covers randomized diff reconstruction, metadata bounds,
latest-request delivery, cancellation, teardown, and a real NSTableView.
Retro-DLP's `ios_collection_test.h` exercises real UITableView row/section
batches, selection restoration, and page updates in its isolated offline app.
Strappy's model-list C harness verifies bounded ID projection order and that
collecting IDs does not fetch display payloads.

Validation on 2026-10-12: shared library and regression executables built for
Mac ppc/i386/x86_64/arm64 and iPhone armv7/arm64. Collection tests passed on the
host Mac, x4-vm (Tiger), and koolphone5. The complete Retro-DLP offline UIKit
suite passed on koolphone5, including row/section batches and exact scroll-offset
preservation for short inset tables. Strappy's offline Linux suite and both
apps' Apple package checks passed. The optional Strappy GNUstep model-row
harness was unavailable in the container (missing GNUstep/Objective-C compiler).
The shared Mac build retains the existing AIWebViewController function-pointer
cast warning; no new collection or consumer warnings were emitted.
