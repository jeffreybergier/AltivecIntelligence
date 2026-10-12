#import "AIPagedRows.h"
NSString * const AIPagedRowsDidLoadNotification = @"AIPagedRowsDidLoadNotification";
@implementation AIPagedRows
- (id)init;
{
  self = [super init];
  if (self) {
    pageReadLock_ = [[NSRecursiveLock alloc] init];
    pageCacheLock_ = [[NSLock alloc] init];
    rowPages_ = [[NSMutableDictionary alloc] init];
    rowPageOrder_ = [[NSMutableArray alloc] init];
    pendingPages_ = [[NSMutableArray alloc] init];
  }
  return self;
}
- (void)dealloc;
{
  [pageReadLock_ release]; [pageCacheLock_ release]; [rowPages_ release];
  [rowPageOrder_ release]; [pendingPages_ release]; [pageError_ release];
  [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone;
{ (void)zone; return [self retain]; }
- (NSArray *)pageAtOffset:(NSUInteger)offset error:(NSError **)error;
{ (void)offset; (void)error; [self doesNotRecognizeSelector:_cmd]; return nil; }
- (NSError *)readError;
{
  NSError *error; [pageCacheLock_ lock]; error = [[pageError_ retain] autorelease];
  [pageCacheLock_ unlock]; return error;
}
- (void)recordReadError:(NSError *)error;
{
  [pageCacheLock_ lock];
  if (!pageError_) pageError_ = [error retain];
  [pageCacheLock_ unlock];
}
- (void)invalidatePages;
{
  [pageCacheLock_ lock]; ++pageGeneration_;
  [rowPages_ removeAllObjects]; [rowPageOrder_ removeAllObjects];
  [pendingPages_ removeAllObjects]; [pageError_ release]; pageError_ = nil;
  [pageCacheLock_ unlock];
}
- (id)cachedObjectAtIndex:(NSUInteger)index;
{
  NSNumber *key = [NSNumber numberWithUnsignedLong:(index / 32) * 32];
  id row = nil; NSArray *page;
  [pageCacheLock_ lock]; page = [rowPages_ objectForKey:key];
  if (index % 32 < [page count]) {
    row = [[[page objectAtIndex:index % 32] retain] autorelease];
    [rowPageOrder_ removeObject:key]; [rowPageOrder_ addObject:key];
  }
  [pageCacheLock_ unlock]; return row;
}
- (void)cachePage:(NSArray *)page key:(NSNumber *)key;
{
  if (![rowPages_ objectForKey:key] && [rowPageOrder_ count] >= 4) {
    [rowPages_ removeObjectForKey:[rowPageOrder_ objectAtIndex:0]];
    [rowPageOrder_ removeObjectAtIndex:0];
  }
  [rowPages_ setObject:page forKey:key];
  [rowPageOrder_ removeObject:key]; [rowPageOrder_ addObject:key];
}
- (NSArray *)validatedPageAtOffset:(NSUInteger)offset error:(NSError **)error;
{
  NSArray *page = [self pageAtOffset:offset error:error];
  NSUInteger count = [self count];
  if (!page || offset > count || [page count] != MIN((NSUInteger)32,count-offset)) {
    if (error && !*error) *error = [NSError errorWithDomain:@"Altivec.QuerySnapshot"
      code:1 userInfo:[NSDictionary dictionaryWithObject:@"The query page does not match its snapshot count."
      forKey:NSLocalizedDescriptionKey]];
    return nil;
  }
  return page;
}
- (id)objectAtIndex:(NSUInteger)index;
{
  id row; NSArray *page; NSError *error = nil;
  NSUInteger offset = (index / 32) * 32;
  unsigned long long generation;
  if (index >= [self count]) [NSException raise:NSRangeException format:@"Row outside snapshot"];
  row = [self cachedObjectAtIndex:index]; if (row) return row;
  if ([self readError]) return [NSDictionary dictionary];
  [pageCacheLock_ lock]; generation = pageGeneration_; [pageCacheLock_ unlock];
  [pageReadLock_ lock]; page = [[self validatedPageAtOffset:offset error:&error] retain];
  [pageReadLock_ unlock];
  [pageCacheLock_ lock];
  if (generation == pageGeneration_ && page) [self cachePage:page key:[NSNumber numberWithUnsignedLong:offset]];
  [pageCacheLock_ unlock];
  if (error) [self recordReadError:error];
  row = index - offset < [page count] ? [[[page objectAtIndex:index-offset] retain] autorelease] : nil;
  [page release];
  /* A failed read has no identity: actions cannot mutate an unrelated row. */
  return row ? row : [NSDictionary dictionary];
}
- (id)requestObjectAtIndex:(NSUInteger)index placeholder:(id)placeholder;
{
  id row = [self cachedObjectAtIndex:index]; BOOL start = NO;
  NSNumber *key;
  if (row || index >= [self count]) return row ? row : placeholder;
  key = [NSNumber numberWithUnsignedLong:(index / 32) * 32];
  [pageCacheLock_ lock];
  if (!pageError_ && ![pendingPages_ containsObject:key]) {
    /* Drop distant prefetch requests when the viewport jumps. */
    if ([pendingPages_ count] >= 4) [pendingPages_ removeObjectAtIndex:0];
    [pendingPages_ addObject:key];
    if (!pageWorker_) { pageWorker_ = YES; start = YES; }
  }
  [pageCacheLock_ unlock];
  if (start) [NSThread detachNewThreadSelector:@selector(loadPages:)
    toTarget:self withObject:nil];
  return placeholder;
}
- (void)loadPages:(id)ignored;
{
  (void)ignored;
  for (;;) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSNumber *key; unsigned long long generation; NSArray *page;
    NSError *error = nil; NSDictionary *result;
    [pageCacheLock_ lock];
    if (![pendingPages_ count]) {
      pageWorker_ = NO; [pageCacheLock_ unlock]; [pool release]; return;
    }
    key = [[pendingPages_ objectAtIndex:0] retain];
    [pendingPages_ removeObjectAtIndex:0]; generation = pageGeneration_;
    [pageCacheLock_ unlock];
    [pageReadLock_ lock]; page = [[self validatedPageAtOffset:[key unsignedLongValue] error:&error] retain];
    [pageReadLock_ unlock];
    result = [NSDictionary dictionaryWithObjectsAndKeys:key, @"offset",
      [NSNumber numberWithUnsignedLongLong:generation], @"generation",
      page ? (id)page : (id)[NSArray array], @"page",
      error ? (id)error : (id)[NSNull null], @"error", nil];
    [self performSelectorOnMainThread:@selector(loadedPage:) withObject:result waitUntilDone:YES];
    [page release]; [key release]; [pool release];
  }
}
- (void)loadedPage:(NSDictionary *)result;
{
  BOOL current; id error = [result objectForKey:@"error"];
  [pageCacheLock_ lock];
  current = [[result objectForKey:@"generation"] unsignedLongLongValue] == pageGeneration_;
  if (current && error == [NSNull null]) [self cachePage:[result objectForKey:@"page"] key:[result objectForKey:@"offset"]];
  [pageCacheLock_ unlock];
  if (!current) return;
  if (error != [NSNull null]) [self recordReadError:error];
  [[NSNotificationCenter defaultCenter] postNotificationName:AIPagedRowsDidLoadNotification object:self userInfo:result];
}
@end
