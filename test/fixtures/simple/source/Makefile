ALTIVEC_ROOT ?= /altivec
include $(ALTIVEC_ROOT)/make/entry.mk
ifeq ($(_altivec_relocated),)
PROJECT_ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST)))/..)
PLATFORM ?= mac
PRODUCTS = Fixture
Fixture_TYPE = app
Fixture_SOURCES = main.c
Fixture_PLIST = Info.plist
Fixture_RESOURCES = message.txt
ifeq ($(PLATFORM),phone)
Fixture_SIGN = 1
endif
include $(ALTIVEC_ROOT)/altivec_common_$(PLATFORM).mk
endif
