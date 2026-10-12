#ifndef AICOLLECTIONTABLEADAPTER_H
#define AICOLLECTIONTABLEADAPTER_H
#import "AICollectionSnapshot.h"

/* Posted by an adapter when one of its current page sources reports an error.
 * userInfo contains the source's error and offset. Delivery is main-thread. */
extern NSString * const AICollectionReadFailedNotification;

/* Composable UIKit/AppKit bridge. Does not replace dataSource/delegate or own
 * cell rendering. The table is borrowed; invalidate before releasing it.
 * AppKit concatenates section rows (section headers remain app-owned rows).
 * Every method requires the main thread. No SQLite dependency. */
@interface AICollectionTableAdapter : NSObject {
  id table_;
  AICollectionSnapshot *snapshot_;
  NSMutableSet *pendingRows_;
  BOOL invalid_, applying_;
}
/* table is UITableView on iOS, NSTableView on Mac (not NSOutlineView). */
- (id)initWithTableView:(id)table;
/* Call immediately after replacing the table data source's model. Applies
 * bounded identity deltas, then refreshes visible content and restores state.
 * Initial/ambiguous changes reload; legacy AppKit uses structural reloads. */
- (void)applySnapshot:(AICollectionSnapshot *)snapshot;
/* Single-section count-only table; identifiers may be nil for safe fallback. */
- (void)applyRowCount:(NSUInteger)count identifiers:(NSArray *)identifiers;
/* Current immutable snapshot, borrowed. */
- (AICollectionSnapshot *)snapshot;
/* Coalesced content refresh for visible rows; never reloads the whole list on
 * a page arrival. Also useful for app-owned editing/presentation changes. */
- (void)refreshVisibleRows;
/* Clears page observers and delayed work; drops snapshot and borrowed table. */
- (void)invalidate;
@end

#endif
