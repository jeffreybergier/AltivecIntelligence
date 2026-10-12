ALTIVEC_ROOT ?= /altivec
PRODUCTS = NotificationTest CollectionTest CollectionBenchmark
CollectionBenchmark_TYPE = executable
CollectionBenchmark_SOURCES = collection_benchmark.m ../AICollectionSnapshot.m
CollectionBenchmark_LDFLAGS = -framework Foundation -framework CoreFoundation -lobjc
CollectionTest_TYPE = executable
CollectionTest_SOURCES = collection_test.m
CollectionTest_COCOA = static
NotificationTest_TYPE = executable
NotificationTest_SOURCES = notification_test.m
NotificationTest_COCOA = static
ifeq ($(TEST_PLATFORM),iOS)
NotificationTest_SIGN = 1
CollectionTest_SIGN = 1
CollectionBenchmark_SIGN = 1
NotificationTest_LDFLAGS = -framework UIKit -framework Foundation -lobjc
CollectionTest_LDFLAGS = -framework UIKit -framework Foundation -lobjc
include $(ALTIVEC_ROOT)/altivec_common_phone.mk
else
NotificationTest_LDFLAGS = -framework AppKit -framework Foundation -lobjc
CollectionTest_LDFLAGS = -framework AppKit -framework Foundation -lobjc
include $(ALTIVEC_ROOT)/altivec_common_mac.mk
endif
