# Validate every archive's requested slice before the linker can ignore it.
link_flags = $(call arch_flags,$(2)) $(if $(filter x86_64,$(2)),-fuse-ld=$(LD64_LLD) -Wl$(comma)-platform_version$(comma)macos$(comma)$(MIN_$(2))$(comma)11.3) $(LDFLAGS) $($(1)_LDFLAGS) $($(1)_LDFLAGS_$(2)) $(if $(call legacy,$(2)),-lgcc_s.10.4) $(if $(filter %.cpp %.cc %.cxx %.mm,$(call sources,$(1),$(2)) $(foreach d,$($(1)_DEPS),$(call sources,$(d),$(2)))),$(if $(call legacy,$(2)),-lstdc++.6,$(if $(filter host,$(2)),-lstdc++,-lc++)))
comma := ,
define slice_rule
$(call slice,$(1),$(2)): $(call objects,$(1),$(2)) $(foreach d,$($(1)_DEPS),$(call slice,$(d),$(2))) $(call static_libs,$(1),$(2)) $($(1)_DYNAMIC_LIBS) $(call product_inputs,$(1)) $(call intermediates,$(1))/$(2)/.config | validate
	@mkdir -p "$$(dir $$@)"
	$(if $(filter static,$($(1)_TYPE)),@rm -f "$$@.tmp",@true)
	$(if $(filter static,$($(1)_TYPE)),$(AR_$(2)) rcs "$$@.tmp" $(call objects,$(1),$(2)),$(ALTIVEC_BUILD_TOOL) slices $(LIPO) $(2) $(call library_deps,$(1),$(2)) $(call static_libs,$(1),$(2)) $($(1)_DYNAMIC_LIBS))
	$(if $(filter static,$($(1)_TYPE)),@mv "$$@.tmp" "$$@",$(CC_$(2)) $(call objects,$(1),$(2)) $(call library_deps,$(1),$(2)) $(call static_libs,$(1),$(2)) $(call link_flags,$(1),$(2)) -o "$$@")
endef
$(foreach p,$(PRODUCTS),$(foreach a,$(ARCHS),$(eval $(call slice_rule,$(p),$(a)))))
define merge_rule
$(call product,$(1)): $(foreach a,$(ARCHS),$(call slice,$(1),$(a))) $(call intermediates,$(1))/.merge-config
	@mkdir -p "$$(dir $$@)"
	$(if $(word 2,$(ARCHS)),$(LIPO) -create $(foreach a,$(ARCHS),$(call slice,$(1),$(a))) -output "$$@",cp "$$<" "$$@")
$(call intermediates,$(1))/.merge-config: FORCE
	@$(ALTIVEC_BUILD_TOOL) stamp "$$@" $(call q,$(ARCHS))
endef
$(foreach p,$(PRODUCTS),$(eval $(call merge_rule,$(p))))
