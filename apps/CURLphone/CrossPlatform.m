#import "CrossPlatform.h"
#import <objc/runtime.h>

@implementation UIProgressView (CrossPlatform)

- (void)XP_setProgress:(float)progress animated:(BOOL)animated;
{
  SEL selector = @selector(setProgress:animated:);
  if ([self respondsToSelector:selector]) {
    typedef void (*MethodPtr)(id, SEL, float, BOOL);
    MethodPtr method = (MethodPtr)[self methodForSelector:selector];
    method(self, selector, progress, animated);
  } else {
    [self setProgress:progress];
  }
}

@end

@implementation NSString (CrossPlatform)

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
