#ifndef AICOLLECTIONOUTLINEADAPTER_H
#define AICOLLECTIONOUTLINEADAPTER_H
#import <TargetConditionals.h>
#if !TARGET_OS_IPHONE
#import <AppKit/AppKit.h>
#import "AICollectionSnapshot.h"
/* Two-level outline bridge. Section IDs are the actual root items, row IDs the
 * actual child items used by the data source. Items must have stable equality.
 * Borrows the outline; main-thread only. Root changes/legacy runtimes reload. */
@interface AICollectionOutlineAdapter : NSObject {
  NSOutlineView *outline_;
  AICollectionSnapshot *snapshot_;
}
/* Does not replace the outline's data source or delegate. */
- (id)initWithOutlineView:(NSOutlineView *)outline;
/* Apply after publishing the matching tree model. Preserves expanded roots,
 * selected items and the top visible item when those items survive. */
- (void)applySnapshot:(AICollectionSnapshot *)snapshot;
/* Content-only refresh of currently visible items. */
- (void)refreshVisibleRows;
/* Drop borrowed view and snapshot before releasing the outline. */
- (void)invalidate;
@end
#endif

#endif
