#import "AltivecCore.h"

#include <string.h>

@implementation AltivecCore

+ (NSString *)certPath;
{
  NSBundle *bundle;
  NSString *certPath;

  bundle = [NSBundle bundleForClass:self];
  certPath = [bundle pathForResource:@"cacert" ofType:@"pem"];
  if (certPath == nil) {
    certPath = [[NSBundle mainBundle] pathForResource:@"cacert"
                                               ofType:@"pem"];
  }
  NSParameterAssert(certPath);
  return certPath;
}

@end

const char *AltivecCoreCertPath(void)
{
  static char *cachedCertPath = NULL;
  NSString *certPath;
  const char *fileSystemPath;

  @synchronized([AltivecCore class]) {
    if (cachedCertPath == NULL) {
      certPath = [AltivecCore certPath];
      fileSystemPath = [certPath fileSystemRepresentation];
      if (fileSystemPath != NULL) {
        cachedCertPath = strdup(fileSystemPath);
      }
    }
  }

  return cachedCertPath;
}
