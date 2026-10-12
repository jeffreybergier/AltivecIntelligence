#ifndef AIPAGEDROWS_H
#define AIPAGEDROWS_H
#import <Foundation/Foundation.h>
extern NSString * const AIPagedRowsDidLoadNotification;
/* Schema-independent, bounded NSArray presentation. Subclasses implement count
 * and pageAtOffset:error: (32 rows, except the final page). Construct/count on a
 * worker before publishing the snapshot. objectAtIndex: is the synchronous
 * compatibility/bulk API; UI callbacks use requestObjectAtIndex:placeholder:.
 * Notifications contain generation and offset, or error. Invalidate when the
 * owner discards a snapshot; pending results from older generations are ignored.
 * Source operations are serialized by pageReadLock_; never hold it on the UI
 * thread for filter changes. Publish a replacement snapshot instead. */
@interface AIPagedRows : NSArray {
@protected
  NSRecursiveLock *pageReadLock_;
@private
  NSLock *pageCacheLock_;
  NSMutableDictionary *rowPages_;
  NSMutableArray *rowPageOrder_, *pendingPages_;
  NSError *pageError_;
  unsigned long long pageGeneration_;
  BOOL pageWorker_;
}
- (NSArray *)pageAtOffset:(NSUInteger)offset error:(NSError **)error;
- (id)cachedObjectAtIndex:(NSUInteger)index;
- (id)requestObjectAtIndex:(NSUInteger)index placeholder:(id)placeholder;
- (void)invalidatePages;
- (NSError *)readError;
/* Subclasses may translate this into an app-specific error notification. */
- (void)recordReadError:(NSError *)error;
@end

#endif
