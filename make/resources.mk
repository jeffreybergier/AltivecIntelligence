# Snapshot resource inventories once per invocation, after library defaults.
$(foreach p,$(PRODUCTS),$(eval _resource_inputs_$(p) := $(call resource_inputs,$(p))))
resource_inputs = $(_resource_inputs_$(1))
# Bundles are reconstructed from named inputs to remove stale resources.
resource_args = $(foreach r,$($(1)_RESOURCE_EXCLUDES),--exclude $(call q,$(r))) $(foreach r,$($(1)_RESOURCES) $($(1)_RESOURCE_BUNDLES),--resource $(call q,$(r))) $(foreach r,$($(1)_FONTS),--font $(call q,$(r))) $(foreach r,$($(1)_LOCALIZATIONS),--localization $(call q,$(r))) $(foreach r,$($(1)_RESOURCE_MAP),--map $(call q,$(r))) $(foreach d,$($(1)_EMBED),--embed $(call q,$(call signed,$(d))=$(or $($(d)_EMBED_PATH),$(if $(filter macOS,$(ALTIVEC_PLATFORM)),Contents/Library/LaunchServices/$(d),$(d))))) $(foreach f,$($(1)_FRAMEWORKS),--framework $(call q,$(f)))
define bundle_rule
$(call intermediates,$(1))/.bundle: $(call signed,$(1)) $(ALTIVEC_ROOT)/make/build.py $(ALTIVEC_ROOT)/make/sign-mac-bundle.sh $($(1)_PLIST) $(call resource_inputs,$(1)) $(foreach r,$($(1)_RESOURCE_MAP),$(firstword $(subst =, ,$(r)))) $(foreach d,$($(1)_EMBED),$(call signed,$(d))) $(call product_inputs,$(1)) $(call intermediates,$(1))/.bundle-config
	$(ALTIVEC_BUILD_TOOL) bundle --platform $(ALTIVEC_PLATFORM) --name $(1) --binary "$(call signed,$(1))" --plist "$($(1)_PLIST)" --output "$(call bundle,$(1))" $(call resource_args,$(1))
	$(if $(call mac_sign,$(1)),bash $(ALTIVEC_ROOT)/make/sign-mac-bundle.sh "$(call bundle,$(1))" $(call q,$($(1)_SIGN_PEM)) $(LIPO) $(foreach d,$($(1)_EMBED),$(call q,$(call bundle,$(1))/$(or $($(d)_EMBED_PATH),Contents/Library/LaunchServices/$(d)))),@true)
	@touch "$$@"
$(call intermediates,$(1))/.bundle-config: FORCE
	@$(ALTIVEC_BUILD_TOOL) stamp "$$@" $(call q,$(call resource_args,$(1)) $(call resource_inputs,$(1)))
endef
