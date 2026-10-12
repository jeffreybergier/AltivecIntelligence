ALTIVEC_ROOT ?= /altivec
PRODUCTS = NotificationTest
NotificationTest_TYPE = executable
NotificationTest_SOURCES = notification_test.m
NotificationTest_COCOA = static
ifeq ($(TEST_PLATFORM),iOS)
NotificationTest_SIGN = 1
NotificationTest_LDFLAGS = -framework UIKit -framework Foundation -lobjc
include $(ALTIVEC_ROOT)/altivec_common_phone.mk
else
NotificationTest_LDFLAGS = -framework AppKit -framework Foundation -lobjc
include $(ALTIVEC_ROOT)/altivec_common_mac.mk
endif
