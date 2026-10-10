# Prebuilt engine libraries are explicit per-product choices: static or dynamic.
ALTIVECCORE_DIR ?= $(ALTIVEC_ROOT)/libs/core/build-$(if $(filter macOS,$(ALTIVEC_PLATFORM)),mac,phone)
ALTIVECCOCOA_DIR ?= $(ALTIVEC_ROOT)/libs/cocoa/build-$(if $(filter macOS,$(ALTIVEC_PLATFORM)),mac,phone)
define engine_libraries
$(1)_FLAGS += $(if $($(1)_CORE),-I$(ALTIVECCORE_DIR)/include) $(if $($(1)_COCOA),-I$(ALTIVECCOCOA_DIR)/include)
$(1)_STATIC_LIBS += $(if $(filter static,$($(1)_COCOA)),$(ALTIVECCOCOA_DIR)/lib/libAltivecCocoa.a) $(if $(filter static,$($(1)_CORE)),$(ALTIVECCORE_DIR)/lib/libAltivecCore.a)
$(1)_LDFLAGS += $(if $(filter dynamic,$($(1)_CORE)),-F$(ALTIVECCORE_DIR)/lib -framework AltivecCore) $(if $(filter dynamic,$($(1)_COCOA)),-F$(ALTIVECCOCOA_DIR)/lib -framework AltivecCocoa) $(if $(filter static,$($(1)_COCOA)),$(if $(filter macOS,$(ALTIVEC_PLATFORM)),-framework WebKit -framework CoreServices -framework ApplicationServices,-framework CoreText))
$(1)_FRAMEWORKS += $(if $(filter dynamic,$($(1)_CORE)),$(ALTIVECCORE_DIR)/lib/AltivecCore.framework) $(if $(filter dynamic,$($(1)_COCOA)),$(ALTIVECCOCOA_DIR)/lib/AltivecCocoa.framework)
$(1)_DYNAMIC_LIBS = $(foreach f,$($(1)_FRAMEWORKS),$(f)/$(basename $(notdir $(f))))
$(1)_RESOURCES += $(if $(and $(filter app,$($(1)_TYPE)),$($(1)_CORE)),$(ALTIVECCORE_DIR)/lib/cacert.pem)
$(1)_FONTS += $(if $(and $(filter app,$($(1)_TYPE)),$(filter static,$($(1)_COCOA))),$(wildcard $(ALTIVECCOCOA_DIR)/Resources/Fonts/*))
endef
$(foreach p,$(PRODUCTS),$(eval $(call engine_libraries,$(p))))

$(foreach p,$(PRODUCTS),$(eval $(p)_DYNAMIC_LIBS := $(foreach f,$($(p)_FRAMEWORKS),$(f)/$(basename $(notdir $(f))))))

ifeq ($(ALTIVEC_PLATFORM),iOS)
$(foreach p,$(PRODUCTS),$(if $(filter dynamic,$($(p)_CORE) $($(p)_COCOA)),$(error iOS product $(p) requires static CORE/COCOA linkage)))
endif
