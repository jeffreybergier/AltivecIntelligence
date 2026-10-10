#include "value.h"
#ifdef USE_SUPPORT
int support(void);
int fixture_cpp(void);
int fixture_objc(void);
int fixture_objcpp(void);
#endif
int main(void) {
#ifdef USE_SUPPORT
  return support() + fixture_cpp() + fixture_objc() + fixture_objcpp() == 48 ? VALUE : 1;
#else
  return VALUE;
#endif
}
