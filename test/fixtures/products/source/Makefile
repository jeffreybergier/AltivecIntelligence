ALTIVEC_ROOT ?= /altivec
include $(ALTIVEC_ROOT)/make/entry.mk
ifeq ($(_altivec_relocated),)
PROJECT_ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST)))/..)
PLATFORM ?= mac
PRODUCTS = Fixture tool support
Fixture_TYPE = app
Fixture_SOURCES = main.c
Fixture_PLIST = Info.plist
Fixture_RESOURCES = message.txt
support_TYPE = static
support_SOURCES = support.c
support_GROUPS = languages
GROUP_languages_SOURCES = sample.cpp sample.m sample.mm
GROUP_languages_CXXFLAGS = -DFIXTURE_CXX=1
GROUP_languages_OBJCFLAGS = -DFIXTURE_OBJC=1
GROUP_languages_OBJCXXFLAGS = -DFIXTURE_OBJCXX=1
tool_TYPE = executable
tool_SOURCES = main.c
tool_DEPS = support
Fixture_DEPS = support
Fixture_FLAGS = -DUSE_SUPPORT
tool_FLAGS = -DUSE_SUPPORT
tool_SIGN = $(if $(filter phone,$(PLATFORM)),1,0)
PACKAGE_PRODUCTS = Fixture tool support
ifeq ($(PLATFORM),phone)
Fixture_SIGN = 1
endif
include $(ALTIVEC_ROOT)/altivec_common_$(PLATFORM).mk
endif
