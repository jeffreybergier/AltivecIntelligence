#import "XPFoundation.h"
#include "model.h"
@implementation XPModel
+ (NSString *)welcome;
{
  return [NSString stringWithFormat:@"%@ (%d)", NSLocalizedString(@"Welcome", nil), model_add(20, 22)];
}
@end
