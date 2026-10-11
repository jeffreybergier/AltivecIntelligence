ALTIVEC_ROOT ?= /altivec
include $(ALTIVEC_ROOT)/make/entry.mk
ifeq ($(_altivec_relocated),)
PRODUCTS = SingleScreen
SingleScreen_TYPE = app
SingleScreen_SOURCES = main.m AppDelegate.m
SingleScreen_PLIST = Resources/Info.plist
SingleScreen_RESOURCES = $(filter-out Resources/Info.plist,$(wildcard Resources/*))
SingleScreen_LDFLAGS = -framework UIKit -framework Foundation -framework CoreGraphics
SingleScreen_SIGN = 1
include $(ALTIVEC_ROOT)/altivec_common_phone.mk
endif
