# Root/child orchestration. Platform directories contain declarations only.
ifndef ALTIVEC_ROOT
ALTIVEC_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
endif
include $(ALTIVEC_ROOT)/make/roots.mk
.DEFAULT_GOAL := release
_project_targets := debug release package analyze validate validate-package print-config clean
.PHONY: clean-all $(_project_targets) all help test-host test-native FORCE
# Each configuration gets an independent child Make context.
$(_project_targets):
	+$(MAKE) --no-print-directory $(addsuffix -$@,$(PLATFORMS))
FORCE:
all: release
define project_targets
.PHONY: $(addprefix $(1)-,$(_project_targets))
$(addprefix $(1)-,$(_project_targets)):
	+$$(MAKE) --no-print-directory -C "$$(PROJECT_ROOT)/$$(PROJECT_$(1)_DIR)" "$$(patsubst $(1)-%,%,$$@)" BUILD_ROOT="$$(BUILD_ROOT)"
endef
$(foreach p,$(PLATFORMS),$(eval $(call project_targets,$(p))))
help:
	@echo 'debug release package clean print-config validate validate-package test-host test-native'
	@echo 'Platforms: $(PLATFORMS); select one with <platform>-<target>.'
test-host:
	$(if $(TEST_HOST_COMMAND),$(TEST_HOST_COMMAND),python3 $(ALTIVEC_ROOT)/test/test_make_products.py)
test-native:
	$(if $(TEST_NATIVE_COMMAND),$(TEST_NATIVE_COMMAND),@echo 'No project native harness declared'; exit 2)

clean-all:
	$(ALTIVEC_BUILD_TOOL) clean $(call q,$(PROJECT_ROOT)) $(call q,$(BUILD_ROOT)) --all
