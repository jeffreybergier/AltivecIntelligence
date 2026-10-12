#import "../AICollectionSnapshot.h"
#import <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>

#define SAMPLES 31
static int compare(const void *a, const void *b)
{
  double x = *(const double *)a, y = *(const double *)b;
  return (x > y) - (x < y);
}
static AICollectionSnapshot *makeSnapshot(NSArray *ids, NSUInteger groups)
{
  NSMutableArray *sections = [NSMutableArray array];
  NSUInteger s, count = [ids count];
  for (s = 0; s < groups; ++s) {
    NSUInteger start = count * s / groups, end = count * (s + 1) / groups;
    NSMutableDictionary *section = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithUnsignedLong:s],@"id",ids,@"rows",
        [NSNumber numberWithUnsignedLong:start],@"offset",
        [NSNumber numberWithUnsignedLong:end-start],@"count",nil];
    if (count <= AICollectionIdentityLimit)
      [section setObject:[ids subarrayWithRange:NSMakeRange(start,end-start)]
                  forKey:@"identifiers"];
    [sections addObject:section];
  }
  return [[AICollectionSnapshot alloc] initWithSections:sections];
}
static void report(const char *name, double *values)
{
  qsort(values,SAMPLES,sizeof(double),compare);
  printf(" %s_ms median=%.3f p95=%.3f",name,values[SAMPLES/2],values[29]);
}
static void measure(NSUInteger count, NSUInteger groups, BOOL strings)
{
  NSAutoreleasePool *outer = [[NSAutoreleasePool alloc] init];
  NSMutableArray *ids = [NSMutableArray array];
  NSMutableArray *fresh = [NSMutableArray array];
  NSUInteger i;
  for (i = 0; i < count; ++i) {
    [ids addObject:strings ? (id)[NSString stringWithFormat:@"model-%08lu",(unsigned long)i] :
        (id)[NSNumber numberWithUnsignedLong:i]];
    /* A query returns equal IDs, not necessarily the same object instances. */
    [fresh addObject:strings ? (id)[NSString stringWithFormat:@"model-%08lu",(unsigned long)i] :
        (id)[NSNumber numberWithUnsignedLong:i]];
  }
  NSMutableArray *next = [[fresh mutableCopy] autorelease];
  [next removeObjectAtIndex:0];
  [next addObject:strings ? (id)@"model-new" : (id)[NSNumber numberWithUnsignedLong:count]];
  NSArray *reverse = [[fresh reverseObjectEnumerator] allObjects];
  AICollectionSnapshot *old = makeSnapshot(ids,groups);
  AICollectionSnapshot *updated = makeSnapshot(next,groups);
  AICollectionSnapshot *reordered = makeSnapshot(reverse,groups);
  double build[SAMPLES], same[SAMPLES], splice[SAMPLES], reorder[SAMPLES];
  /* Warm up once; each measured iteration drains its own temporary objects.
   * Dataset creation, teardown, SQL, table rendering and queue waits are excluded. */
  for (i = 0; i <= SAMPLES; ++i) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    double start = CFAbsoluteTimeGetCurrent();
    AICollectionSnapshot *snapshot = makeSnapshot(fresh,groups);
    double a = (CFAbsoluteTimeGetCurrent() - start) * 1000;
    start = CFAbsoluteTimeGetCurrent();
    (void)[snapshot changesFromSnapshot:old];
    double b = (CFAbsoluteTimeGetCurrent() - start) * 1000;
    start = CFAbsoluteTimeGetCurrent();
    (void)[updated changesFromSnapshot:old];
    double c = (CFAbsoluteTimeGetCurrent() - start) * 1000;
    start = CFAbsoluteTimeGetCurrent();
    (void)[reordered changesFromSnapshot:old];
    double d = (CFAbsoluteTimeGetCurrent() - start) * 1000;
    if (i) { build[i-1]=a; same[i-1]=b; splice[i-1]=c; reorder[i-1]=d; }
    [snapshot release]; [pool drain];
  }
  printf("rows=%lu sections=%lu ids=%s diff=%s",(unsigned long)count,
      (unsigned long)groups,strings ? "string" : "number",
      [old hasCompleteIdentities] ? "enabled" : "fallback");
  report("build",build); report("unchanged",same);
  report("splice",splice); report("reverse",reorder); puts("");
  [old release]; [updated release]; [reordered release]; [outer drain];
}
int main(void)
{
  setvbuf(stdout,NULL,_IONBF,0);
  puts("CollectionBenchmark: 31 samples after warmup; release build; milliseconds");
  measure(100,1,NO); measure(1000,1,NO); measure(4096,1,NO);
  measure(4096,8,YES); measure(21000,1,NO);
  return 0;
}
