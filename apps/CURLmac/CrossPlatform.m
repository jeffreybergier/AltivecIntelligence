#import "CrossPlatform.h"

@implementation NSWindow (CrossPlatform)

- (void)XP_setContentBorderThickness:(float)thickness forEdge:(NSRectEdge)edge;
{
  SEL selector = @selector(setContentBorderThickness:forEdge:);
  if ([self respondsToSelector:selector]) {
    typedef void (*MethodPtr)(id, SEL, float, NSRectEdge);
    MethodPtr method = (MethodPtr)[self methodForSelector:selector];
    method(self, selector, thickness, edge);
  }
}

- (void)XP_setAutorecalculatesContentBorderThickness:(BOOL)flag forEdge:(NSRectEdge)edge;
{
  SEL selector = @selector(setAutorecalculatesContentBorderThickness:forEdge:);
  if ([self respondsToSelector:selector]) {
    typedef void (*MethodPtr)(id, SEL, BOOL, NSRectEdge);
    MethodPtr method = (MethodPtr)[self methodForSelector:selector];
    method(self, selector, flag, edge);
  }
}

@end

@implementation NSString (XPByteCount)

+ (NSString *)XP_stringFromByteCount:(long long)bytes;
{
  if (bytes < 1024) return [NSString stringWithFormat:@"%lld B", bytes];
  
  double count = (double)bytes;
  NSArray *units = [NSArray arrayWithObjects:@"B", @"KB", @"MB", @"GB", @"TB", nil];
  int i = 0;
  
  while (count >= 1024 && i < [units count] - 1) {
    count /= 1024.0;
    i++;
  }
  
  return [NSString stringWithFormat:@"%.2f %@", count, [units objectAtIndex:i]];
}

@end
