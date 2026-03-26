//
//  main.m
//  CURLmac
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

// --- Linker Stubs ---
// This symbol is required by modern Clang for x64 linking when targeting 10.11+
// in environments with legacy runtime libraries.
int __isPlatformVersionAtLeast(int p, int maj, int min, int rev) {
    return 1;
}