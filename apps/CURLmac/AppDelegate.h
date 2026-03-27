#import <AppKit/AppKit.h>
#import "CrossPlatform.h"

@class DownloadWindowController;

@interface AppDelegate : NSObject <XPApplicationDelegate>
{
  DownloadWindowController *_windowController;
}
@end
