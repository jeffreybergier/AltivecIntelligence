ALTIVEC_ROOT ?= /altivec
PRODUCTS = SQLiteFoundationTest
SQLiteFoundationTest_TYPE = executable
SQLiteFoundationTest_SOURCES = foundation_test.m
SQLiteFoundationTest_CORE = static
SQLiteFoundationTest_COCOA = static
SQLiteFoundationTest_SQLITE = 1
SQLiteFoundationTest_LDFLAGS = -framework Foundation -lobjc -lpthread
ifeq ($(TEST_PLATFORM),iOS)
SQLiteFoundationTest_SIGN = 1
include $(ALTIVEC_ROOT)/altivec_common_phone.mk
else
include $(ALTIVEC_ROOT)/altivec_common_mac.mk
endif
