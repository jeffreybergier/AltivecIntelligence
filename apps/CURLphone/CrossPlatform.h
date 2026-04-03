#ifndef CROSS_PLATFORM_H
#define CROSS_PLATFORM_H

#import <UIKit/UIKit.h>

/* --- UIProgressView Cross-Version Category --- */
@interface UIProgressView (CrossPlatform)
- (void)XP_setProgress:(float)progress animated:(BOOL)animated;
@end

/* --- NSString Cross-Version Category --- */
@interface NSString (CrossPlatform)
+ (NSString *)XP_stringFromByteCount:(long long)bytes;
@end

#endif /* CROSS_PLATFORM_H */
