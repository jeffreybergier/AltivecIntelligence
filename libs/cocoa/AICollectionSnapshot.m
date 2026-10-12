#import "AICollectionSnapshot.h"
#include <stdlib.h>
static NSIndexPath *AIPath(NSUInteger section, NSUInteger row)
{
  NSUInteger indexes[2]; indexes[0] = section; indexes[1] = row;
  return [NSIndexPath indexPathWithIndexes:indexes length:2];
}
/* Find the longest common ordered subsequence for unique IDs in O(n log n).
 * Items outside it can be represented safely as deletions and insertions. */
static NSSet *AIKept(NSArray *old, NSArray *next)
{
  NSMutableDictionary *positions = [NSMutableDictionary dictionary];
  NSUInteger i, n = [next count], length = 0;
  for (i = 0; i < [old count]; ++i)
    [positions setObject:[NSNumber numberWithUnsignedLong:i]
                 forKey:[old objectAtIndex:i]];
  NSUInteger *tails = calloc(n + 1, sizeof(NSUInteger));
  NSUInteger *links = calloc(n + 1, sizeof(NSUInteger));
  NSUInteger *values = calloc(n + 1, sizeof(NSUInteger));
  if (!tails || !links || !values) {
    free(tails); free(links); free(values); return [NSSet set];
  }
  for (i = 0; i < n; ++i) {
    NSNumber *value = [positions objectForKey:[next objectAtIndex:i]];
    if (!value) continue;
    NSUInteger lo = 0, hi = length, v = [value unsignedLongValue];
    while (lo < hi) {
      NSUInteger mid = lo + (hi - lo) / 2;
      if (values[tails[mid]] < v) lo = mid + 1; else hi = mid;
    }
    values[i] = v; links[i] = lo ? tails[lo - 1] : NSNotFound;
    tails[lo] = i; if (lo == length) ++length;
  }
  NSMutableSet *kept = [NSMutableSet set];
  i = length ? tails[length - 1] : NSNotFound;
  while (i != NSNotFound) { [kept addObject:[next objectAtIndex:i]]; i = links[i]; }
  free(tails); free(links); free(values); return kept;
}
@implementation AICollectionSnapshot
- (id)initWithSections:(NSArray *)sections;
{
  self = [super init];
  if (self) {
    NSMutableArray *copy = [NSMutableArray array];
    NSMutableDictionary *positions = [NSMutableDictionary dictionary];
    NSMutableSet *sectionIDs = [NSMutableSet set];
    NSUInteger s, total = 0; complete_ = [sections count] <= AICollectionIdentityLimit;
    for (s = 0; s < [sections count]; ++s) {
      NSDictionary *section = [sections objectAtIndex:s];
      NSMutableDictionary *item = [[section mutableCopy] autorelease];
      NSArray *rows = [section objectForKey:@"rows"];
      NSUInteger offset = [[section objectForKey:@"offset"] unsignedLongValue];
      NSUInteger count = [section objectForKey:@"count"] ?
          [[section objectForKey:@"count"] unsignedLongValue] : [rows count];
      if (offset > [rows count] || count > [rows count] - offset) {
        [self release];
        [NSException raise:NSInvalidArgumentException format:@"Invalid collection range"];
        return nil;
      }
      [item setObject:[NSNumber numberWithUnsignedLong:count] forKey:@"count"];
      id sectionID = [section objectForKey:@"id"];
      if (!sectionID || [sectionIDs containsObject:sectionID]) complete_ = NO;
      if (sectionID) [sectionIDs addObject:sectionID];
      NSArray *ids = [section objectForKey:@"identifiers"];
      total = count > AICollectionIdentityLimit - MIN(total,AICollectionIdentityLimit) ?
          AICollectionIdentityLimit + 1 : total + count;
      if (!ids || [ids count] != count || total > AICollectionIdentityLimit)
        complete_ = NO;
      if (ids && total <= AICollectionIdentityLimit && [ids count] <= AICollectionIdentityLimit) {
        [item setObject:[[ids copy] autorelease] forKey:@"identifiers"];
        /* Hash IDs directly. NSArray's hash can be only its count, so using
         * [sectionID,rowID] as a dictionary key makes all rows collide. */
        NSMutableDictionary *rowPositions = [NSMutableDictionary dictionary];
        NSUInteger r;
        for (r = 0; sectionID && r < [ids count]; ++r) {
          id key = [ids objectAtIndex:r];
          if ([rowPositions objectForKey:key]) complete_ = NO;
          [rowPositions setObject:AIPath(s,r) forKey:key];
        }
        if (sectionID) [positions setObject:[[rowPositions copy] autorelease]
                                    forKey:sectionID];
      } else [item removeObjectForKey:@"identifiers"];
      [copy addObject:[[item copy] autorelease]];
    }
    sections_ = [copy copy];
    positions_ = complete_ ? [positions copy] : [[NSDictionary alloc] init];
  }
  return self;
}
- (NSArray *)sections; { return sections_; }
- (NSUInteger)countInSection:(NSUInteger)section;
{ return section < [sections_ count] ? [[[sections_ objectAtIndex:section] objectForKey:@"count"] unsignedLongValue] : 0; }
- (NSUInteger)count;
{
  NSUInteger s, count = 0;
  for (s = 0; s < [sections_ count]; ++s) count += [self countInSection:s];
  return count;
}
- (BOOL)hasCompleteIdentities; { return complete_; }
- (id)identityAtIndexPath:(NSIndexPath *)path;
{
  if (!complete_ || [path length] != 2) return nil;
  NSUInteger s = [path indexAtPosition:0], r = [path indexAtPosition:1];
  if (r >= [self countInSection:s]) return nil;
  NSDictionary *section = [sections_ objectAtIndex:s];
  return [NSArray arrayWithObjects:[section objectForKey:@"id"],
      [[section objectForKey:@"identifiers"] objectAtIndex:r],nil];
}
- (NSIndexPath *)indexPathForIdentity:(id)identity;
{
  if (![identity isKindOfClass:[NSArray class]] || [identity count] != 2)
    return nil;
  return [[positions_ objectForKey:[identity objectAtIndex:0]]
      objectForKey:[identity objectAtIndex:1]];
}
- (NSIndexPath *)indexPathForRow:(NSUInteger)row;
{
  NSUInteger s;
  for (s = 0; s < [sections_ count]; ++s) {
    NSUInteger count = [self countInSection:s];
    if (row < count) return AIPath(s,row);
    row -= count;
  }
  return nil;
}
- (NSUInteger)rowForIndexPath:(NSIndexPath *)path;
{
  if ([path length] != 2) return NSNotFound;
  NSUInteger s = [path indexAtPosition:0], r = [path indexAtPosition:1], i;
  if (r >= [self countInSection:s]) return NSNotFound;
  for (i = 0; i < s; ++i) r += [self countInSection:i];
  return r;
}
- (NSDictionary *)changesFromSnapshot:(AICollectionSnapshot *)previous;
{
  NSDictionary *fallback = [NSDictionary dictionaryWithObject:
      [NSNumber numberWithBool:YES] forKey:@"reload"];
  if (!previous || !complete_ || ![previous hasCompleteIdentities]) return fallback;
  NSArray *old = [previous sections];
  NSArray *oldIDs = [old valueForKey:@"id"], *newIDs = [sections_ valueForKey:@"id"];
  NSSet *kept = AIKept(oldIDs,newIDs);
  NSMutableIndexSet *deleted = [NSMutableIndexSet indexSet];
  NSMutableIndexSet *inserted = [NSMutableIndexSet indexSet];
  NSMutableArray *deletedRows = [NSMutableArray array], *insertedRows = [NSMutableArray array];
  NSUInteger s, r;
  for (s = 0; s < [old count]; ++s)
    if (![kept containsObject:[oldIDs objectAtIndex:s]]) [deleted addIndex:s];
  NSUInteger edits = [deleted count];
  if (edits > 512) return fallback;
  for (s = 0; s < [sections_ count]; ++s) {
    id sectionID = [newIDs objectAtIndex:s];
    if (![kept containsObject:sectionID]) {
      if (++edits > 512) return fallback;
      [inserted addIndex:s]; continue;
    }
    NSUInteger oldSection = [oldIDs indexOfObject:sectionID];
    NSDictionary *before = [old objectAtIndex:oldSection];
    NSDictionary *after = [sections_ objectAtIndex:s];
    id oldTitle = [before objectForKey:@"title"], newTitle = [after objectForKey:@"title"];
    if (oldTitle != newTitle && ![oldTitle isEqual:newTitle]) return fallback;
    NSArray *a = [before objectForKey:@"identifiers"], *b = [after objectForKey:@"identifiers"];
    /* Content refresh is handled by the adapter, even with unchanged IDs. */
    if ([a isEqualToArray:b]) continue;
    NSSet *rows = AIKept(a,b);
    edits += [a count] + [b count] - 2 * [rows count];
    /* Reject large reorders before allocating thousands of index paths. */
    if (edits > 512) return fallback;
    for (r = 0; r < [a count]; ++r)
      if (![rows containsObject:[a objectAtIndex:r]]) [deletedRows addObject:AIPath(oldSection,r)];
    for (r = 0; r < [b count]; ++r)
      if (![rows containsObject:[b objectAtIndex:r]]) [insertedRows addObject:AIPath(s,r)];
  }
  return [NSDictionary dictionaryWithObjectsAndKeys:
      deleted,@"deletedSections",inserted,@"insertedSections",
      deletedRows,@"deletedRows",insertedRows,@"insertedRows",nil];
}
- (void)dealloc;
{ [sections_ release]; [positions_ release]; [super dealloc]; }
@end
