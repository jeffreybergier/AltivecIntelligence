//
//  main.m
//  SingleWindow
//

#import <AppKit/AppKit.h>
#import "AppDelegate.h"

int main(int argc, char *argv[])
{
  // Instantiate
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSApplication *app = [NSApplication sharedApplication];
  AppDelegate *appDelegate = [[[AppDelegate alloc] init] autorelease];
  
  // Configure and Run
  [app setDelegate:appDelegate];
  [app run];
  
  // Close
  [pool release];
  return 0;
}
