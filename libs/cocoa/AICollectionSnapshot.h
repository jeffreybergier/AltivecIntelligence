#ifndef AICOLLECTIONSNAPSHOT_H
#define AICOLLECTIONSNAPSHOT_H
#import <Foundation/Foundation.h>

/* Maximum identity metadata per snapshot for bounded diff work. Large sources
 * stay paged and use structural reload fallback; no payloads are enumerated. */
#define AICollectionIdentityLimit 4096U

/* Immutable table shape, constructed before publication. Each section has:
 * id (unique immutable key), rows (NSArray, often AIPagedRows), optional offset
 * and count (range within rows), optional identifiers (one stable unique key per
 * displayed row). Optional pageSource/pageOffset map wrapped row arrays onto
 * their AIPagedRows publisher. title is optional presentation metadata.
 * Count-only forms may omit rows and provide an explicit count.
 * A table owner must update its data source BEFORE applying this snapshot.
 * Each owner has its own sources; do not mutate a published snapshot's rows. */
@interface AICollectionSnapshot : NSObject {
  NSArray *sections_;
  NSDictionary *positions_;
  BOOL complete_;
  NSObject *identity_;
  NSLock *changesLock_;
  id previousIdentity_;
  NSDictionary *preparedChanges_;
}
/* Copies metadata, retains row sources; never reads row payloads or executes SQL. */
- (id)initWithSections:(NSArray *)sections;
/* Immutable section metadata; no database calls. */
- (NSArray *)sections;
/* Count in one displayed section, or zero for an invalid section. */
- (NSUInteger)countInSection:(NSUInteger)section;
/* Total displayed rows; AppKit adapter concatenates sections without headers. */
- (NSUInteger)count;
/* YES only for complete, bounded, unique identity metadata. */
- (BOOL)hasCompleteIdentities;
/* Section/row pair expressed as a two-component Foundation NSIndexPath. */
- (id)identityAtIndexPath:(NSIndexPath *)path;
/* Identity is scoped by section; nil if missing or ambiguous. */
- (NSIndexPath *)indexPathForIdentity:(id)identity;
/* Converts between a flat AppKit row and section/row coordinates. */
- (NSIndexPath *)indexPathForRow:(NSUInteger)row;
- (NSUInteger)rowForIndexPath:(NSIndexPath *)path;
/* Pure bounded diff. Keys: reload (BOOL), deletedSections/insertedSections
 * (NSIndexSet), deletedRows/insertedRows (NSIndexPath arrays). Moves become
 * delete+insert; deletions use old coordinates, insertions use new coordinates.
 * Missing/duplicate IDs or excessive edits request a full reload. */
- (NSDictionary *)changesFromSnapshot:(AICollectionSnapshot *)previous;
/* Worker-only preparation. Reads immutable metadata, never row payloads/UI.
 * Keeps only the previous identity token, not a chain of old row sources. */
- (void)prepareChangesFromSnapshot:(AICollectionSnapshot *)previous;
/* Returns a prepared diff only for this exact previous snapshot, otherwise nil.
 * Thread-safe, bounded lookup; adapters use reload fallback when absent. */
- (NSDictionary *)preparedChangesFromSnapshot:(AICollectionSnapshot *)previous;
@end

#endif
