# Always sign a copy; each executable owns its entitlements.
mac_sign = $(and $(filter macOS,$(ALTIVEC_PLATFORM)),$(or $(filter 1,$($(1)_MAC_SIGN) $($(1)_SIGN)),$($(1)_ENTITLEMENTS)))
signed = $(if $(filter static,$($(1)_TYPE)),$(call product,$(1)),$(INT_DIR)/$(1)/signed/$(1))
define sign_rule
$(call signed,$(1)): $(call product,$(1)) $(ALTIVEC_ROOT)/make/build.py $($(1)_ENTITLEMENTS) $($(1)_SIGN_PLIST) $($(1)_SIGN_PEM) $(INT_DIR)/$(1)/.sign-config
	@mkdir -p "$$(dir $$@)"
	@cp "$$<" "$$@"
	$(if $(call mac_sign,$(1)),$(ALTIVEC_BUILD_TOOL) mac-sign "$$@" $(LIPO) $(call q,$($(1)_IDENTIFIER)) $(call q,$($(1)_SIGN_PLIST)) $(call q,$($(1)_SIGN_PEM)) $(call q,$($(1)_ENTITLEMENTS)),@true)
	$(if $(and $(filter-out macOS,$(ALTIVEC_PLATFORM)),$(or $($(1)_ENTITLEMENTS),$(filter 1,$($(1)_SIGN)))),$(LDID) -S$($(1)_ENTITLEMENTS) "$$@",@true)
$(INT_DIR)/$(1)/.sign-config: FORCE
	@$(ALTIVEC_BUILD_TOOL) stamp "$$@" $(call q,$(LDID) $($(1)_ENTITLEMENTS) $($(1)_SIGN) $($(1)_SANDBOX) $($(1)_MAC_SIGN) $($(1)_IDENTIFIER) $($(1)_SIGN_PLIST) $($(1)_SIGN_PEM))
endef
$(foreach p,$(PRODUCTS),$(if $(filter static,$($(p)_TYPE)),,$(eval $(call sign_rule,$(p)))))
$(foreach p,$(PRODUCTS),$(if $(filter app,$($(p)_TYPE)),$(eval $(call bundle_rule,$(p)))))
