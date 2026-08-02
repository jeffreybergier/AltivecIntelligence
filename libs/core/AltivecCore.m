#import "AltivecCore.h"

#include <string.h>

@implementation AltivecCore

+ (NSString *)certPath;
{
  return [AICURLConnection certPath];
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
