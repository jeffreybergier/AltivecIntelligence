ALTIVEC_ROOT ?= /altivec
include $(ALTIVEC_ROOT)/make/entry.mk
ifeq ($(_altivec_relocated),)
PROJECT_ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
PLATFORMS = native
PROJECT_native_DIR = source
include $(ALTIVEC_ROOT)/make/projects.mk
endif
