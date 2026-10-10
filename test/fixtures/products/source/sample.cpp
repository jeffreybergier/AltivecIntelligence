#ifndef FIXTURE_CXX
#error Missing C++ group flags
#endif
#include <vector>
extern "C" int fixture_cpp(void) { std::vector<int> values(1, 1); return values[0]; }
