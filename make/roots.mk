# Resolve overrides once against the declaring project, then inherit absolute paths.
PROJECT_ROOT ?= $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
ifeq ($(strip $(PROJECT_ROOT)),)
$(error PROJECT_ROOT must not be empty)
endif
ifneq (x$(PROJECT_ROOT)x,x$(strip $(PROJECT_ROOT))x)
$(error PROJECT_ROOT must not contain leading or trailing whitespace)
endif
ifneq ($(words $(PROJECT_ROOT)),1)
$(error PROJECT_ROOT must not contain whitespace; GNU Make paths are whitespace-delimited)
endif
override PROJECT_ROOT := $(abspath $(PROJECT_ROOT))
BUILD_ROOT ?= build
ifeq ($(strip $(BUILD_ROOT)),)
$(error BUILD_ROOT must not be empty)
endif
ifneq (x$(BUILD_ROOT)x,x$(strip $(BUILD_ROOT))x)
$(error BUILD_ROOT must not contain leading or trailing whitespace)
endif
ifneq ($(words $(BUILD_ROOT)),1)
$(error BUILD_ROOT must not contain whitespace; GNU Make paths are whitespace-delimited)
endif
override BUILD_ROOT := $(abspath $(if $(filter /%,$(BUILD_ROOT)),$(BUILD_ROOT),$(PROJECT_ROOT)/$(BUILD_ROOT)))
export PROJECT_ROOT BUILD_ROOT
BUILD_VARIANT ?=
ifneq ($(strip $(BUILD_VARIANT)),)
q = '$(subst ','"'"',$(1))'
_variant_valid := $(shell printf '%s' $(call q,$(BUILD_VARIANT)) | LC_ALL=C tr -d 'a-zA-Z0-9_-')
ifneq ($(_variant_valid),)
$(error BUILD_VARIANT must contain only letters, digits, underscores or hyphens)
endif
endif
q = '$(subst ','"'"',$(1))'
ALTIVEC_BUILD_TOOL := python3 $(ALTIVEC_ROOT)/make/build.py
_root_error := $(shell $(ALTIVEC_BUILD_TOOL) check-root $(call q,$(PROJECT_ROOT)) $(call q,$(BUILD_ROOT)) 2>&1)
ifneq ($(_root_error),)
$(error $(_root_error))
endif
