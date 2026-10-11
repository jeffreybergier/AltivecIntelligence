package_inputs = $(shell $(ALTIVEC_BUILD_TOOL) inputs $(foreach r,$($(1)_PACKAGE_RESOURCES) $($(1)_PACKAGE_FILES),$(call q,$(firstword $(subst =, ,$(r))))))
$(foreach p,$(PRODUCTS),$(eval _package_inputs_$(p) := $(call package_inputs,$(p))))
package_inputs = $(_package_inputs_$(1))
# Format and sandbox policy are independent. No implicit Debian architecture.
formats = $(or $($(1)_PACKAGES),$(if $(filter app,$($(1)_TYPE)),$(if $(filter macOS,$(ALTIVEC_PLATFORM)),zip,ipa),zip))
package = $(call product_dir,$(1))/$(or $($(1)_ARCHIVE_NAME),$(1))$(if $(filter deb-%,$(2)),-$(patsubst deb-%,%,$(2)).deb,.$(2))
package_args = --main-path $(call q,$($(1)_PACKAGE_MAIN_PATH)) $(foreach r,$($(1)_PACKAGE_RESOURCES),--extra $(call q,$(r))) $(foreach r,$($(1)_PACKAGE_FILES),--package-file $(call q,$(r))) --name $(1) --platform $(ALTIVEC_PLATFORM) --format $(2) --input $(call q,$(if $(filter app,$($(1)_TYPE)),$(call bundle,$(1)),$(call signed,$(1)))) --output $(call q,$(call package,$(1),$(2))) --prefix $(call q,$(or $($(1)_PREFIX_$(2)),$(if $(filter deb-rootless,$(2)),/var/jb))) --architecture $(call q,$($(1)_PACKAGE_ARCH)) --package-id $(call q,$($(1)_PACKAGE_ID)) --version $(call q,$($(1)_VERSION)) --maintainer $(call q,$(or $($(1)_MAINTAINER),Altivec Intelligence)) --description $(call q,$(or $($(1)_DESCRIPTION),$(1))) --compression $(call q,$(or $($(1)_COMPRESSION),gzip)) --owner $(call q,$(or $($(1)_OWNER),0:0)) --lifecycle $(call q,$($(1)_LIFECYCLE)) $(foreach d,$($(1)_INSTALL),--install $(call q,$(call signed,$(d))=$(or $($(d)_INSTALL_PATH),usr/libexec/$(d)))) $(foreach f,$($(1)_LAUNCHD),--launchd $(call q,$(f))) $(foreach f,$($(1)_PACKAGE_SCRIPTS),--script $(call q,$(f)))
define package_rule
$(call package,$(1),$(2)): $(if $(filter app,$($(1)_TYPE)),$(call intermediates,$(1))/.bundle,$(call signed,$(1))) $(foreach d,$($(1)_INSTALL),$(call signed,$(d))) $($(1)_LAUNCHD) $($(1)_PACKAGE_SCRIPTS) $($(1)_LIFECYCLE) $(call package_inputs,$(1)) $(call intermediates,$(1))/.$(2)-config $(ALTIVEC_ROOT)/make/build.py
	$(ALTIVEC_BUILD_TOOL) package $(call package_args,$(1),$(2))
$(call intermediates,$(1))/.$(2)-config: FORCE
	@$(ALTIVEC_BUILD_TOOL) stamp "$$@" $(call q,$(call package_args,$(1),$(2)) $(call package_inputs,$(1)))
endef
PACKAGE_PRODUCTS ?= $(filter-out $(foreach p,$(PRODUCTS),$($(p)_DEPS) $($(p)_EMBED) $($(p)_INSTALL)),$(PRODUCTS))
$(foreach p,$(PACKAGE_PRODUCTS),$(foreach f,$(call formats,$(p)),$(eval $(call package_rule,$(p),$(f)))))
PACKAGES = $(foreach p,$(PACKAGE_PRODUCTS),$(foreach f,$(call formats,$(p)),$(call package,$(p),$(f))))

# Validate the extracted payload, including each embedded/installed executable.
installed_prefix = $(patsubst /%,%,$(or $($(1)_PREFIX_$(2)),$(if $(filter deb-rootless,$(2)),/var/jb)))
payload_root = $(if $(filter ipa,$(2)),Payload/,$(if $(filter deb-%,$(2)),$(if $(call installed_prefix,$(1),$(2)),$(call installed_prefix,$(1),$(2))/)$(if $(filter app,$($(1)_TYPE)),Applications/,usr/libexec/)))
main_binary = $(call payload_root,$(1),$(2))$(if $(filter app,$($(1)_TYPE)),$(1).app/$(if $(filter macOS,$(ALTIVEC_PLATFORM)),Contents/MacOS/))$(or $($(1)_PACKAGE_MAIN_PATH),$(if $(filter static,$($(1)_TYPE)),lib$(1).a,$(1)))
validation_args = --lipo $(LIPO) --ldid $(LDID) $(foreach a,$(if $(filter-out linux,$(ALTIVEC_PLATFORM)),$(ARCHS)),--arch $(a)) --binary-check $(call q,$(call main_binary,$(1),$(2))|$($(1)_ENTITLEMENTS)) $(foreach d,$($(1)_EMBED),--binary-check $(call q,$(call payload_root,$(1),$(2))$(1).app/$(or $($(d)_EMBED_PATH),$(if $(filter macOS,$(ALTIVEC_PLATFORM)),Contents/Library/LaunchServices/$(d),$(d)))|$($(d)_ENTITLEMENTS))) $(foreach d,$($(1)_INSTALL),--binary-check $(call q,$(if $(call installed_prefix,$(1),$(2)),$(call installed_prefix,$(1),$(2))/)$(or $($(d)_INSTALL_PATH),usr/libexec/$(d))|$($(d)_ENTITLEMENTS)))
define validation_rule
.PHONY: validate-$(1)-$(2)
validate-$(1)-$(2): $(call package,$(1),$(2))
	$(ALTIVEC_BUILD_TOOL) validate-one $(call package_args,$(1),$(2)) $(call validation_args,$(1),$(2))
_validate-package: validate-$(1)-$(2)
endef
$(foreach p,$(PACKAGE_PRODUCTS),$(foreach f,$(call formats,$(p)),$(eval $(call validation_rule,$(p),$(f)))))
