ALTIVEC_ROOT ?= /altivec
include $(ALTIVEC_ROOT)/make/entry.mk
ifeq ($(_altivec_relocated),)
PRODUCTS = SingleWindow
SingleWindow_TYPE = app
SingleWindow_SOURCES = main.m AppDelegate.m
SingleWindow_PLIST = Resources/Info.plist
SingleWindow_RESOURCES = $(filter-out Resources/Info.plist,$(wildcard Resources/*))
SingleWindow_LDFLAGS = -framework AppKit -lobjc
include $(ALTIVEC_ROOT)/altivec_common_mac.mk
endif
