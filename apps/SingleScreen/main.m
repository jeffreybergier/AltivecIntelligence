#import <UIKit/UIKit.h>
#import "AppDelegate.h"

int main(int argc, char * argv[]) {
  @autoreleasepool {
    const char *delegateClass = [NSStringFromClass([AppDelegate class]) 
      UTF8String];
    return UIApplicationMain(argc, argv, nil, 
      [NSString stringWithUTF8String:delegateClass]);
  }
}
