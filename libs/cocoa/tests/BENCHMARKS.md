# Collection snapshot benchmark — 2026-10-12

The identity map now stores section ID → row ID → index path. It no longer
hashes two-element NSArray keys, whose identical hashes caused quadratic
construction. The public identity token and app-facing API are unchanged.
Unchanged ID arrays skip diff construction, and diffs exceeding the edit budget
return the reload fallback before allocating individual row index paths.

## Method

`collection_benchmark.m` runs 31 samples after one warmup for each dataset using
release (`-O3`) builds. Both hosts ran the same universal executable: arm64 on
this Mac (macOS 15.7.3), ppc on x4-vm (Mac OS X 10.4.11, build 8S165). Values are
wall-clock milliseconds; VM scheduling and machine load affect the tails.
Inputs for old/new snapshots are materialized separately with equal values.

Build timing includes section metadata creation and snapshot initialization.
Diff timings cover unchanged IDs, removing the first ID and appending a new ID,
and reversing the IDs. Input generation, object teardown, SQL, worker queue
waits, and native table rendering/reload costs are excluded. With eight sections,
the splice also crosses section boundaries. Reversals exceeding 512 edits
return a full-reload decision; the subsequent table reload is not timed.

Each cell below is **median / p95**. Numeric IDs use one section; string IDs
use eight sections. These are measurements, not portable pass/fail budgets.

## This Mac

| Rows / IDs | Build | Unchanged diff | Splice diff | Reverse diff |
|---|---:|---:|---:|---:|
| 100 / numeric | 0.066 / 0.179 | 0.007 / 0.020 | 0.152 / 0.470 | 0.140 / 0.375 |
| 1,000 / numeric | 0.217 / 0.501 | 0.004 / 0.020 | 0.532 / 1.344 | 0.275 / 0.811 |
| 4,096 / numeric | 0.412 / 0.551 | 0.005 / 0.007 | 1.031 / 1.373 | 0.523 / 0.715 |
| 4,096 / strings | 0.798 / 0.856 | 0.058 / 0.063 | 1.849 / 1.988 | 0.103 / 0.111 |

An earlier exploratory benchmark of the original implementation on this Mac
measured 1,414 ms median construction at 4,096 numeric IDs (101 iterations).
The new result is roughly 3,400 times faster. That older run used a slightly
simpler one-section metadata wrapper; it is not a paired statistical trial.

## x4-vm

| Rows / IDs | Build | Unchanged diff | Splice diff | Reverse diff |
|---|---:|---:|---:|---:|
| 100 / numeric | 0.528 / 0.615 | 0.176 / 0.367 | 0.705 / 0.890 | 1.027 / 1.211 |
| 1,000 / numeric | 7.786 / 8.077 | 1.215 / 1.340 | 7.629 / 9.134 | 5.819 / 6.169 |
| 4,096 / numeric | 79.254 / 155.027 | 5.015 / 11.587 | 28.935 / 31.496 | 20.088 / 31.712 |
| 4,096 / strings | 31.917 / 76.426 | 1.424 / 1.847 | 35.923 / 68.478 | 2.845 / 3.116 |

In this 2026-10-12 baseline, construction ran on the collection worker and
diffing ran on the UI thread: 1,000-row small edits are within a 16.7 ms frame interval in these
samples, but 4,096-row edits can cause a visible hitch on x4-vm even before table
rendering. Unchanged-list checks are considerably cheaper. This is not evidence
that every supported machine or workload is always fast. As of 2026-10-14, list controllers can prepare comparison on the worker after
main-thread receipt; table/outline adapters consume matching prepared changes
without computing a diff. Immediate unprepared updates reload safely. These
historical CPU timings do not measure the new scheduling or total UI latency.

Before the two diff fast paths were added, this VM's 4,096-row numeric reversal
took 160.866 ms median (288.167 ms p95). Early fallback reduces that to 20.088 ms
median. For 21,000 rows, identity metadata is omitted: build/fallback-decision
medians are 0.001/<0.001 ms here and 0.051/0.004 ms on x4-vm. This does **not**
measure loading or displaying 21,000 rows.

## Reproduction and regression checks

Inside the existing Altivec SDK container:

```sh
make -C /work/AltivecIntelligence/libs/cocoa/tests release
```

Run `libs/cocoa/tests/build/macOS/release/CollectionBenchmark/CollectionBenchmark`
on the host, or copy it to a fresh directory under `~/Desktop` on x4-vm and
execute it there. The benchmark compiles the current snapshot source directly;
the companion `CollectionTest` links the shared library, which must be rebuilt
first after library changes.

The host-only alternative is:

```sh
clang -O3 -Wno-semicolon-before-method-body \
  libs/cocoa/tests/collection_benchmark.m libs/cocoa/AICollectionSnapshot.m \
  -framework Foundation -framework CoreFoundation -o /tmp/CollectionBenchmark
/tmp/CollectionBenchmark
```

`collection_test.m` counts identity equality comparisons rather than imposing
machine-dependent timing assertions. It fails against the original map and
passes with the fix, including equal-but-distinct keys, section-scoped identities,
missing IDs, duplicate detection, unchanged snapshots, and reorder fallback.
The full collection suite passed on this Mac and x4-vm. Library and test builds
passed for ppc/i386/x86_64/arm64 Mac and armv7/arm64 iPhone. No new warnings; the
existing AIWebViewController function-pointer cast warning remains.
