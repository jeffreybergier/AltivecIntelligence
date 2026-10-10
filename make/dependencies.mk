q ?= '$(subst ','"'"',$(1))'
# Supported legacy dependency adapters build isolated copies of pinned checkouts.
DEPENDENCY_ROOT = $(BUILD_ROOT)/dependencies/$(ALTIVEC_PLATFORM)/$(CONFIG)
LIBICAL_SOURCE ?= $(PROJECT_ROOT)/source/deps/libical
LIBVC_SOURCE ?= $(PROJECT_ROOT)/source/deps/libvc
LIBICAL_PREPARED = $(DEPENDENCY_ROOT)/libical-3.0.20
LIBVC_PREPARED = $(DEPENDENCY_ROOT)/libvc-source
LIBICAL_FLAGS = -I$(LIBICAL_PREPARED)/src/libical
LIBVC_FLAGS = -I$(LIBVC_PREPARED)/src
external_arch = $(if $(filter iOS,$(ALTIVEC_PLATFORM)),ios-)$(1)
libical = $(DEPENDENCY_ROOT)/libical-$(call external_arch,$(1))/lib/libical.a
libvc = $(DEPENDENCY_ROOT)/libvc-$(call external_arch,$(1))/libvc.a
external_toolchain = $(if $(filter ppc i386,$(1)),$(ALTIVEC_LEGACY_TOOLCHAIN),$(ALTIVEC_MODERN_TOOLCHAIN))
define prepare_dependency
$(DEPENDENCY_ROOT)/$(1)-source.stamp: $(shell find $(2) -type f ! -name .git 2>/dev/null) $(wildcard $(ALTIVEC_ROOT)/make/dependencies/$(1)*) $(ALTIVEC_ROOT)/make/dependencies/build-$(1).sh
	@mkdir -p "$$(dir $$@)"
	ALTIVEC_DEPENDENCY_SOURCE=$(2) bash $(ALTIVEC_ROOT)/make/dependencies/build-$(1).sh prepare $(DEPENDENCY_ROOT)
endef
ifneq ($(filter libical,$(DEPENDENCIES)),)
$(eval $(call prepare_dependency,libical,$(LIBICAL_SOURCE)))
endif
ifneq ($(filter libvc,$(DEPENDENCIES)),)
$(eval $(call prepare_dependency,libvc,$(LIBVC_SOURCE)))
endif
define external_library
$(call $(1),$(2)): $(DEPENDENCY_ROOT)/$(1)-source.stamp $(ALTIVEC_ROOT)/make/dependencies/build-$(1).sh $(DEPENDENCY_ROOT)/$(1)-$(call external_arch,$(2)).config
	ALTIVEC_DEPENDENCY_CC=$(call q,$(CC_$(2))) ALTIVEC_DEPENDENCY_SDK=$(call q,$(SDK_$(2))) ALTIVEC_DEPENDENCY_MIN=$(call q,$(MIN_$(2))) bash $(ALTIVEC_ROOT)/make/dependencies/build-$(1).sh $(call external_arch,$(2)) $(DEPENDENCY_ROOT) $(call external_toolchain,$(2))
$(DEPENDENCY_ROOT)/$(1)-$(call external_arch,$(2)).config: FORCE
	@python3 $(ALTIVEC_ROOT)/make/build.py stamp "$$@" $(call q,$(CC_$(2)) $(SDK_$(2)) $(MIN_$(2)))
endef
$(foreach d,$(DEPENDENCIES),$(foreach a,$(ARCHS),$(eval $(call external_library,$(d),$(a)))))
# Declare generated headers as compile prerequisites, not just link inputs.
$(foreach p,$(PRODUCTS),$(foreach a,$(ARCHS),$(eval $(p)_COMPILE_INPUTS_$(a) += $(foreach d,$($(p)_DEPENDENCIES),$(call $(d),$(a))))))
$(foreach p,$(PRODUCTS),$(foreach a,$(ARCHS),$(eval $(p)_STATIC_LIBS_$(a) += $(foreach d,$($(p)_DEPENDENCIES),$(call $(d),$(a))))))
$(foreach p,$(PRODUCTS),$(foreach a,$(ARCHS),$(eval $(p)_FLAGS_$(a) += $(if $(filter libical,$($(p)_DEPENDENCIES)),$(LIBICAL_FLAGS) -I$(DEPENDENCY_ROOT)/libical-$(call external_arch,$(a))/src) $(if $(filter libvc,$($(p)_DEPENDENCIES)),$(LIBVC_FLAGS)))))

$(LIBICAL_PREPARED)/zoneinfo: $(DEPENDENCY_ROOT)/libical-source.stamp
	@test -d "$@"

.PHONY: FORCE
FORCE:

# A preparation step can replace the generated resource tree while parallel
# Make checks its previously enumerated children. Give each child the producer.
$(LIBICAL_PREPARED)/zoneinfo/%: | $(DEPENDENCY_ROOT)/libical-source.stamp
	@test -e "$@"
