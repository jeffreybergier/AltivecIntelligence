# One object per product, configuration, architecture, and source; real depfiles.
lang = $(if $(filter %.cpp %.cc %.cxx,$(1)),CXX,$(if $(filter %.mm,$(1)),OBJCXX,$(if $(filter %.m,$(1)),OBJC,C)))
legacy = $(filter ppc i386,$(1))
arch_flags = $(if $(filter-out host,$(1)),-arch $(1) -isysroot $(SDK_$(1)) $(if $(call legacy,$(1)),-mmacosx-version-min=$(MIN_$(1)),-target $(1)-apple-$(if $(filter macOS,$(ALTIVEC_PLATFORM)),macos,ios)$(MIN_$(1))) $(if $(filter iOS,$(ALTIVEC_PLATFORM)),-B$(MODERN_BIN)))
compile_flags = $(OPT_FLAGS) -g -Wall -Wextra $(if $(call legacy,$(2)),-fno-stack-protector -fno-common -fno-zero-initialized-in-bss,$(if $(filter-out host,$(2)),-Wno-semicolon-before-method-body)) $(if $(filter CXX OBJCXX,$(call lang,$(3))),$(if $(filter-out host ppc i386,$(2)),-stdlib=libc++)) $(if $(filter C OBJC,$(call lang,$(3))),-std=c99) $(CPPFLAGS) $(BUILD_FLAGS) $($(call lang,$(3))FLAGS) $($(1)_FLAGS) $($(1)_FLAGS_$(2)) $($(1)_$(call lang,$(3))FLAGS) $($(1)_$(call lang,$(3))FLAGS_$(2)) $(foreach g,$(call source_group,$(1),$(2),$(3)),$(GROUP_$(g)_FLAGS) $(GROUP_$(g)_FLAGS_$(2)) $(GROUP_$(g)_$(call lang,$(3))FLAGS)) $(if $(filter OBJC OBJCXX,$(call lang,$(3))),$(if $(filter arc,$(foreach g,$(call source_group,$(1),$(2),$(3)),$(GROUP_$(g)_MEMORY))),-fobjc-arc,$(if $(call legacy,$(2)),,-fno-objc-arc)))
$(foreach a,$(ARCHS),$(eval CXX_$(a) ?= $(patsubst %clang,%clang++,$(patsubst %gcc,%g++,$(CC_$(a))))))
compiler = $(if $(filter CXX OBJCXX,$(call lang,$(3))),$(CXX_$(2)),$(CC_$(2)))

define compile_rule
$(call object,$(1),$(2),$(3)): $(call resolve_source,$(3)) $(call product_inputs,$(1)) $($(1)_COMPILE_INPUTS_$(2)) $(INT_DIR)/$(1)/$(2)/.config | validate
	@mkdir -p "$$(dir $$@)"
	@echo '  > $(1) $(2): $(3)'
	$(call compiler,$(1),$(2),$(3)) $(call arch_flags,$(2)) $(call compile_flags,$(1),$(2),$(3)) -MMD -MP -MF "$$@.d" -c "$$<" -o "$$@"
endef
# Config stamps compare content; command-line flags and removed sources invalidate objects.
define config_rule
$(INT_DIR)/$(1)/$(2)/.config: FORCE
	@$(ALTIVEC_BUILD_TOOL) stamp "$$@" $(call q,$(CC_$(2)) $(AR_$(2)) $(LD64_LLD) $(LDFLAGS) $($(1)_TYPE) $(call arch_flags,$(2)) $(foreach s,$(call sources,$(1),$(2)),$(s) $(call compiler,$(1),$(2),$(s)) $(call compile_flags,$(1),$(2),$(s))) $($(1)_LDFLAGS) $($(1)_LDFLAGS_$(2)) $(call static_libs,$(1),$(2)) $($(1)_DEPS))
endef
$(foreach p,$(PRODUCTS),$(foreach a,$(ARCHS),$(eval $(call config_rule,$(p),$(a)))$(foreach s,$(call sources,$(p),$(a)),$(eval $(call compile_rule,$(p),$(a),$(s))))))
-include $(foreach p,$(PRODUCTS),$(foreach a,$(ARCHS),$(addsuffix .d,$(call objects,$(p),$(a)))))
