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
