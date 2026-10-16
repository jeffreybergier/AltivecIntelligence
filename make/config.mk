include $(ALTIVEC_ROOT)/make/roots.mk
CONFIG ?= release
ifneq ($(words $(CONFIG)),1)
$(error CONFIG must select exactly one configuration)
endif
ifeq ($(filter $(CONFIG),debug release),)
$(error CONFIG must be debug or release)
endif
OUTPUT_DIR ?= $(BUILD_ROOT)/$(ALTIVEC_PLATFORM)/$(CONFIG)$(if $(BUILD_VARIANT),/variants/$(BUILD_VARIANT))
output_name = $(or $($(1)_OUTPUT_NAME),$(if $(filter static,$($(1)_TYPE)),lib)$(1))
product_dir = $(OUTPUT_DIR)/$(call output_name,$(1))
intermediates = $(call product_dir,$(1))/Intermediates
ANALYZE_DIR = $(BUILD_ROOT)/analyze/$(ALTIVEC_PLATFORM)$(if $(BUILD_VARIANT),/variants/$(BUILD_VARIANT))
TEST_ROOT = $(BUILD_ROOT)/tests/$(ALTIVEC_PLATFORM)
GENERATED_DIR = $(OUTPUT_DIR)/generated
analysis = $(ANALYZE_DIR)/$(call output_name,$(1))/$(patsubst /%,%,$(abspath $(call resolve_source,$(2)))).plist
OPT_FLAGS ?= $(if $(filter debug,$(CONFIG)),-O0,-O3)
ARCHS ?= $(if $(filter linux,$(ALTIVEC_PLATFORM)),host,$(if $(filter macOS,$(ALTIVEC_PLATFORM)),ppc i386 x86_64 arm64,armv7 arm64))
ifneq ($(filter-out $(if $(filter linux,$(ALTIVEC_PLATFORM)),host,$(if $(filter macOS,$(ALTIVEC_PLATFORM)),ppc i386 x86_64 arm64,armv7 arm64)),$(ARCHS)),)
$(error Unsupported ARCHS=$(ARCHS) for $(ALTIVEC_PLATFORM))
endif
ifeq ($(strip $(ARCHS)),)
$(error ARCHS must not be empty)
endif
SDK_ppc ?= $(SDK_PPC_PATH)
SDK_i386 ?= $(SDK_X86_PATH)
SDK_x86_64 ?= $(SDK_X64_PATH)
SDK_armv7 ?= $(SDK_IOS_PATH)
SDK_arm64 ?= $(if $(filter macOS,$(ALTIVEC_PLATFORM)),$(SDK_ARM64_PATH),$(SDK_IOS_PATH))
MIN_ppc ?= 10.4
MIN_i386 ?= 10.4
MIN_x86_64 ?= 10.9
MIN_armv7 ?= 5.0
MIN_arm64 ?= $(if $(filter macOS,$(ALTIVEC_PLATFORM)),11.0,7.0)
CC_ppc ?= $(COMPILER_PPC)
CC_i386 ?= $(COMPILER_X86)
CC_x86_64 ?= $(COMPILER_X64)
CC_armv7 ?= $(COMPILER_IOS)
CC_arm64 ?= $(if $(filter macOS,$(ALTIVEC_PLATFORM)),$(COMPILER_ARM64),$(COMPILER_IOS))
AR_ppc ?= $(AR_LEGACY)
AR_i386 ?= $(AR_LEGACY)
AR_x86_64 ?= $(AR_MODERN)
AR_arm64 ?= $(AR_MODERN)
AR_armv7 ?= $(AR_MODERN)
# The host ~/.altivec directory is the container home (/root).
ALTIVEC_SIGNING_PEM ?= $(wildcard $(HOME)/signing/development.pem)
ifeq ($(ALTIVEC_PLATFORM),macOS)
$(foreach p,$(PRODUCTS),$(eval $(p)_SIGN_PEM ?= $$(ALTIVEC_SIGNING_PEM)))
endif
LDID ?= ldid
export OSXCROSS_NO_DSYMUTIL=1
export ZERO_AR_DATE=1
ALTIVEC_BUILD_TOOL := python3 $(ALTIVEC_ROOT)/make/build.py
# Quote a shell argument, including embedded single quotes.
q = '$(subst ','"'"',$(1))'
resolve_source = $(or $(firstword $(wildcard $(1) $(addsuffix /$(1),$(SOURCE_DIRS)))),$(1))
sources = $($(1)_SOURCES) $(foreach g,$($(1)_GROUPS),$(GROUP_$(g)_SOURCES)) $($(1)_SOURCES_$(2))
source_group = $(foreach g,$($(1)_GROUPS),$(if $(filter $(3),$(GROUP_$(g)_SOURCES)),$(g)))
# Encode full source paths; preserve extension to distinguish foo.c/foo.cpp.
object = $(call intermediates,$(1))/$(2)/$(patsubst /%,%,$(abspath $(call resolve_source,$(3)))).o
objects = $(foreach s,$(call sources,$(1),$(2)),$(call object,$(1),$(2),$(s)))
slice = $(call intermediates,$(1))/$(2)/$(if $(filter static,$($(1)_TYPE)),lib$(1).a,$(1))
product = $(call product_dir,$(1))/$(if $(filter static,$($(1)_TYPE)),lib$(1).a,$(1))
bundle = $(call product_dir,$(1))/$(1).app
library_deps = $(foreach d,$($(1)_DEPS),$(if $(filter static,$($(d)_TYPE)),$(call slice,$(d),$(2))))
static_libs = $($(1)_STATIC_LIBS) $($(1)_STATIC_LIBS_$(2))
product_inputs = $($(1)_INPUTS) $($(1)_GENERATED) $(foreach g,$($(1)_GROUPS),$(GROUP_$(g)_INPUTS))
resource_inputs = $(shell $(ALTIVEC_BUILD_TOOL) inputs $(foreach f,$($(1)_RESOURCES) $($(1)_RESOURCE_BUNDLES) $($(1)_FONTS) $($(1)_LOCALIZATIONS) $($(1)_FRAMEWORKS) $(foreach r,$($(1)_RESOURCE_MAP),$(firstword $(subst =, ,$(r)))), $(call q,$(f))))
$(foreach p,$(PRODUCTS),$(if $(filter $($(p)_TYPE),app executable daemon static),,$(error $(p)_TYPE must be app, executable, daemon or static)))
$(foreach p,$(PRODUCTS),$(if $(filter-out $(PRODUCTS),$($(p)_DEPS) $($(p)_EMBED)),$(error Unknown dependency of $(p))))

_product_error := $(shell $(ALTIVEC_BUILD_TOOL) names $(foreach p,$(PRODUCTS),$(call q,$(call output_name,$(p)))) 2>&1)
ifneq ($(_product_error),)
$(error $(_product_error))
endif
