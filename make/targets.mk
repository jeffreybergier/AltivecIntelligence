# Independent recursive configurations make `-j debug release` safe.
ENTRY_MAKEFILE := $(abspath $(firstword $(MAKEFILE_LIST)))
.PHONY: debug release all package validate help print-config clean test-host test-native validate-package FORCE
FORCE:
debug release:
	+$(MAKE) --no-print-directory -f $(ENTRY_MAKEFILE) package CONFIG=$@ BUILD_ROOT=$(call q,$(BUILD_ROOT))
all: package
package:
	+$(ALTIVEC_BUILD_TOOL) guard $(call q,$(PROJECT_ROOT)) $(call q,$(BUILD_ROOT)) $(call q,$(OUTPUT_DIR)) $(MAKE) --no-print-directory -f $(call q,$(ENTRY_MAKEFILE)) _package
.PHONY: _package _analyze clean-all
_package: $(PACKAGES)
validate:
	@$(ALTIVEC_BUILD_TOOL) safe-root $(call q,$(PROJECT_ROOT)) $(call q,$(BUILD_ROOT))
	@$(foreach a,$(ARCHS),test -n '$(CC_$(a))' && test -x '$(CC_$(a))' && test -d '$(SDK_$(a))' || { echo 'Missing compiler or SDK for $(a): $(CC_$(a)) $(SDK_$(a))'; exit 1; };)
	@$(foreach g,$(sort $(foreach p,$(PRODUCTS),$($(p)_GROUPS))),$(if $(filter arc,$(GROUP_$(g)_MEMORY)),test '$(ALTIVEC_PLATFORM)' = iOS || { echo 'ARC group $(g) requires iOS'; exit 1; };)) true
	@$(foreach a,$(ARCHS),$(ALTIVEC_BUILD_TOOL) floor $(ALTIVEC_PLATFORM) $(a) $(MIN_$(a)) &&) true
	@$(foreach p,$(PRODUCTS),$(ALTIVEC_BUILD_TOOL) policy $(call q,$($(p)_SANDBOX)) $(call q,$($(p)_ENTITLEMENTS)) &&) true
help:
	@echo 'debug release package clean clean-all print-config validate validate-package test-host test-native'
	@echo 'ARCHS="ppc i386" or ARCHS=arm64; BUILD_ROOT is relative to PROJECT_ROOT.'
print-config:
	@echo 'project=$(PROJECT_ROOT) platform=$(ALTIVEC_PLATFORM) config=$(CONFIG) output=$(OUTPUT_DIR)'
	@$(foreach a,$(ARCHS),echo '$(a): compiler=$(CC_$(a)) CXX=$(CXX_$(a)) AR=$(AR_$(a)) SDK=$(SDK_$(a)) minimum=$(MIN_$(a))';)
	@$(foreach p,$(PRODUCTS),echo '$(p): type=$($(p)_TYPE) deps=$($(p)_DEPS) output=$(call product,$(p))'; echo ' sandbox=$($(p)_SANDBOX) formats=$(call formats,$(p)) package-architecture=$($(p)_PACKAGE_ARCH)'; echo ' inputs=$(call product_inputs,$(p)) plist=$($(p)_PLIST) entitlements=$($(p)_ENTITLEMENTS) resources=$(call resource_inputs,$(p))'; $(foreach a,$(ARCHS),echo ' $(a): sources=$(call sources,$(p),$(a)) libraries=$(call static_libs,$(p),$(a))';))
	@echo 'packages=$(PACKAGES)'
clean:
	$(if $(and $(PRODUCT),$(filter-out $(PRODUCTS),$(PRODUCT))),$(error Unknown PRODUCT=$(PRODUCT) for $(ALTIVEC_PLATFORM)))
	$(ALTIVEC_BUILD_TOOL) clean $(call q,$(PROJECT_ROOT)) $(call q,$(BUILD_ROOT)) $(ALTIVEC_PLATFORM) $(if $(PRODUCT),$(call q,$(call output_name,$(PRODUCT))))
clean-all:
	$(ALTIVEC_BUILD_TOOL) clean $(call q,$(PROJECT_ROOT)) $(call q,$(BUILD_ROOT)) --all
test-host:
	$(if $(TEST_HOST_COMMAND),$(TEST_HOST_COMMAND),$(if $(filter-out $(CURDIR),$(PROJECT_ROOT)),$(MAKE) -C $(PROJECT_ROOT) test-host,python3 $(ALTIVEC_ROOT)/test/test_make_products.py))
test-native:
	$(if $(TEST_NATIVE_COMMAND),$(TEST_NATIVE_COMMAND),$(if $(filter-out $(CURDIR),$(PROJECT_ROOT)),$(MAKE) -C $(PROJECT_ROOT) test-native,@echo 'Set TEST_NATIVE_COMMAND to the project offline native harness'; exit 2))
validate-package:
	+$(ALTIVEC_BUILD_TOOL) guard $(call q,$(PROJECT_ROOT)) $(call q,$(BUILD_ROOT)) $(call q,$(OUTPUT_DIR)) $(MAKE) --no-print-directory -f $(call q,$(ENTRY_MAKEFILE)) _validate-package
.PHONY: _validate-package
_validate-package: _package
	$(ALTIVEC_BUILD_TOOL) validate $(PACKAGES)

# Named product targets expose the same graph used by packages.
define product_target
.PHONY: $(1)
$(1):
	+$$(ALTIVEC_BUILD_TOOL) guard $$(call q,$$(PROJECT_ROOT)) $$(call q,$$(BUILD_ROOT)) $$(call q,$$(OUTPUT_DIR)) $$(MAKE) --no-print-directory -f $$(call q,$$(ENTRY_MAKEFILE)) _product-$(1)
.PHONY: _product-$(1)
_product-$(1): $(if $(filter app,$($(1)_TYPE)),$(call intermediates,$(1))/.bundle,$(call signed,$(1)))
endef
$(foreach p,$(PRODUCTS),$(eval $(call product_target,$(p))))
ANALYZER ?= $(COMPILER_IOS)
ANALYZE_ARCH ?= $(if $(filter linux,$(ALTIVEC_PLATFORM)),host,$(or $(firstword $(filter x86_64 arm64 armv7,$(ARCHS))),i386))
.PHONY: analyze
analyze:
	+$(ALTIVEC_BUILD_TOOL) guard $(call q,$(PROJECT_ROOT)) $(call q,$(BUILD_ROOT)) $(call q,$(ANALYZE_DIR)) $(MAKE) --no-print-directory -f $(call q,$(ENTRY_MAKEFILE)) _analyze
_analyze: validate $(foreach p,$(PRODUCTS),$(call product_inputs,$(p)) $($(p)_COMPILE_INPUTS_$(ANALYZE_ARCH)))
	@$(foreach p,$(PRODUCTS),mkdir -p $(call q,$(ANALYZE_DIR)/$(call output_name,$(p))) &&) true
	$(foreach p,$(PRODUCTS),$(foreach s,$(call sources,$(p),$(ANALYZE_ARCH)),mkdir -p $(call q,$(dir $(call analysis,$(p),$(s)))) && $(ANALYZER) --analyze $(call arch_flags,$(ANALYZE_ARCH)) $(call compile_flags,$(p),$(ANALYZE_ARCH),$(s)) $(call q,$(call resolve_source,$(s))) -o $(call q,$(call analysis,$(p),$(s))) &&)) true

.PHONY: run-tests linux test
linux:
	+$(MAKE) -f $(ENTRY_MAKEFILE) PLATFORM=host release
test: test-host
run-tests: $(foreach p,$(TEST_PRODUCTS),$(call signed,$(p)))
	$(foreach p,$(TEST_PRODUCTS),$(or $($(p)_TEST_COMMAND),$(call signed,$(p))) &&) true
