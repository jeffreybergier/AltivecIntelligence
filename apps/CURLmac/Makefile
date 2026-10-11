ALTIVEC_ROOT ?= /altivec
include $(ALTIVEC_ROOT)/make/entry.mk
ifeq ($(_altivec_relocated),)
PRODUCTS = CURLmac
CURLmac_TYPE = app
CURLmac_SOURCES = main.m DownloadWindowController.m AICURLConnection.m
CURLmac_PLIST = Resources/Info.plist
CURLmac_RESOURCES = $(filter-out Resources/Info.plist,$(wildcard Resources/*))
CURLmac_LDFLAGS = -framework AppKit -lobjc
CURLmac_CORE = dynamic
CURLmac_COCOA = dynamic
include $(ALTIVEC_ROOT)/altivec_common_mac.mk
endif
