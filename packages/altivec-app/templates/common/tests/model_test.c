#include "model.h"
#include <assert.h>
#include <limits.h>
#include <string.h>
int main(void) {
  assert(model_add(2, 3) == 5);
  assert(model_add(2, -3) == -1);
  assert(model_add(INT_MAX, 1) == INT_MAX);
  assert(model_add(INT_MIN, -1) == INT_MIN);
  assert(strcmp(model_version(), "1") == 0);
  return 0;
}
