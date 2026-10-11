ALTIVEC_ROOT ?= /altivec
include $(ALTIVEC_ROOT)/make/entry.mk
ifeq ($(_altivec_relocated),)
PROJECT_ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST)))/..)
PLATFORM ?= mac
PRODUCTS = Fixture helper
Fixture_TYPE = app
Fixture_SOURCES = main.c
Fixture_PLIST = Info.plist
Fixture_RESOURCES = message.txt
helper_TYPE = daemon
helper_SOURCES = helper.c
Fixture_EMBED = helper
ifeq ($(PLATFORM),phone)
Fixture_ENTITLEMENTS = AppEntitlements.plist
helper_ENTITLEMENTS = HelperEntitlements.plist
endif
include $(ALTIVEC_ROOT)/altivec_common_$(PLATFORM).mk
endif
