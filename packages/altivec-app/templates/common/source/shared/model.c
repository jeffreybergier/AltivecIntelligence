#include "model.h"
#include <limits.h>
int model_add(int value, int delta) {
  if (delta > 0 && value > INT_MAX - delta) return INT_MAX;
  if (delta < 0 && value < INT_MIN - delta) return INT_MIN;
  return value + delta;
}
const char *model_version(void) { return "1"; }
