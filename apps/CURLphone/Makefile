ALTIVEC_ROOT ?= /altivec
include $(ALTIVEC_ROOT)/make/entry.mk
ifeq ($(_altivec_relocated),)
PRODUCTS = CURLphone
CURLphone_TYPE = app
CURLphone_GROUPS = ui
GROUP_ui_SOURCES = main.m DownloadViewController.m CrossPlatform.m AICURLConnection.m
CURLphone_PLIST = Resources/Info.plist
CURLphone_RESOURCES = $(filter-out Resources/Info.plist,$(wildcard Resources/*))
CURLphone_LDFLAGS = -framework UIKit -framework Foundation -framework CoreGraphics
CURLphone_CORE = static
CURLphone_COCOA = static
CURLphone_SIGN = 1
include $(ALTIVEC_ROOT)/altivec_common_phone.mk
endif
