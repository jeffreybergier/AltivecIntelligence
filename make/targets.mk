# Independent recursive configurations make `-j debug release` safe.
ENTRY_MAKEFILE := $(firstword $(MAKEFILE_LIST))
.PHONY: debug release all package validate help print-config clean test-host test-native validate-package FORCE
FORCE:
debug release:
	+$(MAKE) --no-print-directory -f $(ENTRY_MAKEFILE) package CONFIG=$@ BUILD_ROOT=$(call q,$(BUILD_ROOT))
all package: $(PACKAGES)
validate:
	@$(ALTIVEC_BUILD_TOOL) safe-root $(call q,$(PROJECT_ROOT)) $(call q,$(BUILD_ROOT))
	@$(foreach a,$(ARCHS),test -n '$(CC_$(a))' && test -x '$(CC_$(a))' && test -d '$(SDK_$(a))' || { echo 'Missing compiler or SDK for $(a): $(CC_$(a)) $(SDK_$(a))'; exit 1; };)
	@$(foreach g,$(sort $(foreach p,$(PRODUCTS),$($(p)_GROUPS))),$(if $(filter arc,$(GROUP_$(g)_MEMORY)),test '$(ALTIVEC_PLATFORM)' = iOS || { echo 'ARC group $(g) requires iOS'; exit 1; };)) true
	@$(foreach a,$(ARCHS),$(ALTIVEC_BUILD_TOOL) floor $(ALTIVEC_PLATFORM) $(a) $(MIN_$(a)) &&) true
	@$(foreach p,$(PRODUCTS),$(ALTIVEC_BUILD_TOOL) policy $(call q,$($(p)_SANDBOX)) $(call q,$($(p)_ENTITLEMENTS)) &&) true
help:
	@echo 'debug release package clean print-config validate validate-package test-host test-native'
	@echo 'ARCHS="ppc i386" or ARCHS=arm64; BUILD_ROOT is relative to PROJECT_ROOT.'
print-config:
	@echo 'project=$(PROJECT_ROOT) platform=$(ALTIVEC_PLATFORM) config=$(CONFIG) output=$(OUTPUT_DIR)'
	@$(foreach a,$(ARCHS),echo '$(a): compiler=$(CC_$(a)) CXX=$(CXX_$(a)) AR=$(AR_$(a)) SDK=$(SDK_$(a)) minimum=$(MIN_$(a))';)
	@$(foreach p,$(PRODUCTS),echo '$(p): type=$($(p)_TYPE) deps=$($(p)_DEPS) output=$(call product,$(p))'; echo ' sandbox=$($(p)_SANDBOX) formats=$(call formats,$(p)) package-architecture=$($(p)_PACKAGE_ARCH)'; echo ' inputs=$(call product_inputs,$(p)) plist=$($(p)_PLIST) entitlements=$($(p)_ENTITLEMENTS) resources=$(call resource_inputs,$(p))'; $(foreach a,$(ARCHS),echo ' $(a): sources=$(call sources,$(p),$(a)) libraries=$(call static_libs,$(p),$(a))';))
	@echo 'packages=$(PACKAGES)'
clean:
	$(ALTIVEC_BUILD_TOOL) clean $(call q,$(PROJECT_ROOT)) $(call q,$(BUILD_ROOT)) $(ALTIVEC_PLATFORM)
test-host:
	$(if $(TEST_HOST_COMMAND),$(TEST_HOST_COMMAND),$(if $(filter-out $(CURDIR),$(PROJECT_ROOT)),$(MAKE) -C $(PROJECT_ROOT) test-host,python3 $(ALTIVEC_ROOT)/test/test_make_products.py))
test-native:
	$(if $(TEST_NATIVE_COMMAND),$(TEST_NATIVE_COMMAND),$(if $(filter-out $(CURDIR),$(PROJECT_ROOT)),$(MAKE) -C $(PROJECT_ROOT) test-native,@echo 'Set TEST_NATIVE_COMMAND to the project offline native harness'; exit 2))
validate-package: package
	$(ALTIVEC_BUILD_TOOL) validate $(PACKAGES)

# Named product targets expose the same graph used by packages.
define product_target
.PHONY: $(1)
$(1): $(if $(filter app,$($(1)_TYPE)),$(INT_DIR)/$(1)/.bundle,$(call signed,$(1)))
endef
$(foreach p,$(PRODUCTS),$(eval $(call product_target,$(p))))
ANALYZE_ARCH ?= $(or $(firstword $(filter x86_64 arm64 armv7,$(ARCHS))),i386)
.PHONY: analyze
analyze: validate $(foreach p,$(PRODUCTS),$(call product_inputs,$(p)) $($(p)_COMPILE_INPUTS_$(ANALYZE_ARCH)))
	@mkdir -p $(OUTPUT_DIR)/analyze
	$(foreach p,$(PRODUCTS),$(foreach s,$(call sources,$(p),$(ANALYZE_ARCH)),$(COMPILER_IOS) --analyze $(call arch_flags,$(ANALYZE_ARCH)) $(call compile_flags,$(p),$(ANALYZE_ARCH),$(s)) $(call q,$(call resolve_source,$(s))) -o $(OUTPUT_DIR)/analyze/$(p)-$(notdir $(s)).plist &&)) true

.PHONY: run-tests linux test
linux:
	+$(MAKE) -f $(ENTRY_MAKEFILE) PLATFORM=host release
test: test-host
run-tests: $(foreach p,$(TEST_PRODUCTS),$(call signed,$(p)))
	$(foreach p,$(TEST_PRODUCTS),$(or $($(p)_TEST_COMMAND),$(call signed,$(p))) &&) true
