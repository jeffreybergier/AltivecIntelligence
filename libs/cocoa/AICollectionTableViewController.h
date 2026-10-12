#ifndef AICOLLECTIONTABLEVIEWCONTROLLER_H
#define AICOLLECTIONTABLEVIEWCONTROLLER_H
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import "AICollectionTableAdapter.h"

/* Optional UIKit owner for collection-backed screens, including small forms.
 * Subclasses retain their normal UITableView data source and cell rendering. */
@interface AICollectionTableViewController : UITableViewController {
  AICollectionTableAdapter *collectionTableAdapter_;
}
/* Borrowed adapter, created lazily after the table has loaded. */
- (AICollectionTableAdapter *)collectionTableAdapter;
/* Apply after changing the data source. Also called on appearance. */
- (void)refreshCollection;
/* Override for paged sources or worker-built metadata. Default uses only the
 * data source's section/row counts and the identity hooks below. */
- (NSArray *)collectionSections;
/* Override when sections can move. Default is a positional section key. */
- (id)collectionIdentifierForSection:(NSInteger)section;
/* Return bounded stable row IDs. Default nil requests safe reload fallback.
 * Never enumerate lazy row payloads here to discover identities. */
- (NSArray *)collectionIdentifiersForSection:(NSInteger)section;
/* Convenience for fixed forms whose row roles never move within a section.
 * Dynamic lists must supply domain IDs instead of positional identities. */
- (NSArray *)collectionFixedIdentifiersForSection:(NSInteger)section;
@end
#endif

#endif
