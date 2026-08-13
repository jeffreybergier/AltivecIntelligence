# Altivec Toolchain common rules for a sandboxed iOS application IPA.
#
# A project Makefile defines APP_NAME and SOURCES, optionally adds RESOURCES,
# BUNDLE_LOCALIZATION_DIRS, and FRAMEWORKS, then includes this file.  The
# supported public targets are:
#
#   release   Build and sign build-release/APP_NAME.app, then package its IPA.
#   analyze   Run Clang's static analyzer and write build-analyze/analyze.txt.
#   clean     Remove build-release and build-analyze.

ifndef ALTIVEC_IOS_APP_MK_INCLUDED
ALTIVEC_IOS_APP_MK_INCLUDED := 1

SHELL := /bin/bash
.DEFAULT_GOAL := release

_altivec_ios_mk_path := $(abspath $(lastword $(MAKEFILE_LIST)))
_altivec_ios_mk_dir := $(dir $(_altivec_ios_mk_path))

# Installed at /var/altivec/share/altivec/make/ios-app.mk.  Deriving the
# prefix keeps the rules relocatable for local validation and future layouts.
ALTIVEC_PREFIX ?= $(abspath $(_altivec_ios_mk_dir)/../../..)
ALTIVEC_BIN ?= $(ALTIVEC_PREFIX)/bin
ALTIVEC_CC ?= $(ALTIVEC_BIN)/clang
ALTIVEC_CXX ?= $(ALTIVEC_BIN)/clang++
ALTIVEC_LDID ?= $(ALTIVEC_BIN)/ldid
ALTIVEC_ZIP ?= $(ALTIVEC_BIN)/zip

# altivec-lib writes this fragment whenever a managed library version is
# selected.  Builds consume it when present but never download or update
# libraries themselves.  Set ALTIVEC_LIBS=none for a project-level opt-out.
ALTIVEC_LIBS ?= auto
ALTIVEC_LIB_MAKEFILE ?= \
	$(ALTIVEC_PREFIX)/share/altivec-lib/current.mk
_altivec_managed_libs_enabled := \
	$(if $(filter 0 no NO false FALSE none NONE,$(strip $(ALTIVEC_LIBS))),,1)
ifneq ($(_altivec_managed_libs_enabled),)
-include $(ALTIVEC_LIB_MAKEFILE)
endif

ALTIVEC_MANAGED_VERSION ?=
ALTIVEC_MANAGED_ROOT ?=
ALTIVEC_MANAGED_INCLUDE_DIRS ?=
ALTIVEC_MANAGED_ARCHIVES ?=
ALTIVEC_MANAGED_FRAMEWORKS ?=
ALTIVEC_MANAGED_BUNDLE_DIR ?=
ALTIVEC_MANAGED_RESOURCE_FILES ?=

SDKROOT ?= $(ALTIVEC_PREFIX)/SDKs/Current.sdk
IPHONEOS_DEPLOYMENT_TARGET ?= 5.0
ALTIVEC_ARCH ?= armv7

# Clang recognizes an SDK's platform from a name such as iPhoneOS8.4.sdk.
# Resolve Current.sdk before invoking it so the convenient selection symlink
# does not trigger -Wincompatible-sysroot.
_altivec_resolved_sdkroot := $(realpath $(SDKROOT))
_altivec_effective_sdkroot := \
	$(if $(_altivec_resolved_sdkroot),$(_altivec_resolved_sdkroot),$(SDKROOT))
_altivec_build_variant := \
	$(notdir $(_altivec_effective_sdkroot))-$(ALTIVEC_ARCH)-ios$(IPHONEOS_DEPLOYMENT_TARGET)

INFO_PLIST ?= Info.plist
RESOURCE_ROOT ?= Resources
RESOURCES ?=
BUNDLE_LOCALIZATION_DIRS ?=
# Localization roots may live beside the platform target, for example under
# ../shared/Resources.  Bound them to the owning repository before copying.
APP_PROJECT_ROOT ?= $(CURDIR)
FRAMEWORKS ?=
INCLUDE_DIRS ?=

# UIKit applications nearly always need these three.  FRAMEWORKS is for the
# app's additional dependencies, such as Security or CoreLocation.
ALTIVEC_BASE_FRAMEWORKS := Foundation UIKit CoreGraphics

# Optional project-controlled additions.  The common rules retain ownership
# of the architecture, SDK, optimization, and packaging flags.
APP_CPPFLAGS ?=
APP_CFLAGS ?=
APP_CXXFLAGS ?=
APP_OBJCFLAGS ?=
APP_LDFLAGS ?=
APP_LDLIBS ?=
APP_ANALYZE_FLAGS ?=
APP_USE_ARC ?= 1

ifeq ($(strip $(APP_NAME)),)
$(error APP_NAME must be defined before including $(_altivec_ios_mk_path))
endif
ifneq ($(findstring /,$(APP_NAME)),)
$(error APP_NAME must not contain a slash: $(APP_NAME))
endif

_altivec_release_dir := $(CURDIR)/build-release
_altivec_analyze_dir := $(CURDIR)/build-analyze
_altivec_object_dir := \
	$(_altivec_release_dir)/Intermediates/Objects/$(_altivec_build_variant)
_altivec_analyze_log_dir := \
	$(_altivec_analyze_dir)/Logs/$(_altivec_build_variant)
_altivec_app_dir := $(_altivec_release_dir)/$(APP_NAME).app
_altivec_app_executable := $(_altivec_app_dir)/$(APP_NAME)
_altivec_ipa_path := $(_altivec_release_dir)/$(APP_NAME).ipa
_altivec_ipa_stage := $(_altivec_release_dir)/.ipa-stage
_altivec_analyze_report := $(_altivec_analyze_dir)/analyze.txt

_altivec_supported_sources := \
	$(filter %.c %.m %.cc %.cpp %.cxx %.mm,$(SOURCES))
_altivec_unsupported_sources := \
	$(filter-out %.c %.m %.cc %.cpp %.cxx %.mm,$(SOURCES))
_altivec_cxx_sources := \
	$(filter %.cc %.cpp %.cxx %.mm,$(_altivec_supported_sources))

# Encode source paths into flat, deterministic object/log names.  This lets a
# project use ../Shared/Foo.m without allowing an object path to escape the
# build directory.
_altivec_encode_path = \
	$(subst :,_,$(subst /,__,$(subst ..,__up__,$(basename $(1)))))
_altivec_object_for = \
	$(_altivec_object_dir)/$(call _altivec_encode_path,$(1)).o
_altivec_analyze_log_for = \
	$(_altivec_analyze_log_dir)/$(call _altivec_encode_path,$(1)).txt

_altivec_objects := \
	$(foreach source,$(_altivec_supported_sources),\
		$(call _altivec_object_for,$(source)))
_altivec_analyze_logs := \
	$(foreach source,$(_altivec_supported_sources),\
		$(call _altivec_analyze_log_for,$(source)))

ifneq ($(words $(_altivec_objects)),$(words $(sort $(_altivec_objects))))
$(error SOURCES contains paths which map to the same object name)
endif

_altivec_target_triple := \
	$(ALTIVEC_ARCH)-apple-ios$(IPHONEOS_DEPLOYMENT_TARGET)
_altivec_target_flags := \
	--target=$(_altivec_target_triple) \
	-arch $(ALTIVEC_ARCH) \
	-miphoneos-version-min=$(IPHONEOS_DEPLOYMENT_TARGET) \
	-isysroot $(_altivec_effective_sdkroot) \
	-B$(ALTIVEC_BIN)
_altivec_include_flags := \
	$(foreach directory,$(INCLUDE_DIRS) $(ALTIVEC_MANAGED_INCLUDE_DIRS),\
		-I$(directory))
_altivec_framework_flags := \
	$(foreach framework,$(ALTIVEC_BASE_FRAMEWORKS) $(FRAMEWORKS) \
		$(ALTIVEC_MANAGED_FRAMEWORKS),\
		-framework $(framework))
_altivec_arc_flag := \
	$(if $(filter 1 YES yes true TRUE,$(APP_USE_ARC)),-fobjc-arc)
_altivec_makefiles := $(abspath $(MAKEFILE_LIST))
_altivec_resource_inputs := \
	$(foreach resource,$(RESOURCES),$(RESOURCE_ROOT)/$(resource))
_altivec_localization_dirs := \
	$(foreach directory,$(BUNDLE_LOCALIZATION_DIRS),\
		$(wildcard $(directory)/*.lproj))
_altivec_localization_inputs := \
	$(BUNDLE_LOCALIZATION_DIRS) $(_altivec_localization_dirs) \
	$(foreach directory,$(_altivec_localization_dirs),\
		$(wildcard $(directory)/*))
_altivec_managed_inputs := \
	$(ALTIVEC_MANAGED_ARCHIVES) $(ALTIVEC_MANAGED_RESOURCE_FILES)

_altivec_compiler_for = \
	$(if $(filter %.cc %.cpp %.cxx %.mm,$(1)),\
		$(ALTIVEC_CXX),$(ALTIVEC_CC))
_altivec_language_flags_for = \
	$(if $(filter %.m,$(1)),\
		$(APP_CFLAGS) $(APP_OBJCFLAGS) $(_altivec_arc_flag),\
		$(if $(filter %.mm,$(1)),\
			$(APP_CXXFLAGS) $(APP_OBJCFLAGS) $(_altivec_arc_flag),\
			$(if $(filter %.cc %.cpp %.cxx,$(1)),\
				$(APP_CXXFLAGS),$(APP_CFLAGS))))
_altivec_link_driver := \
	$(if $(_altivec_cxx_sources),$(ALTIVEC_CXX),$(ALTIVEC_CC))

.PHONY: release analyze clean __altivec_ios_validate

release: $(_altivec_ipa_path)
	@printf 'Application: %s\nIPA: %s\n' \
		"$(_altivec_app_dir)" "$(_altivec_ipa_path)"

analyze: $(_altivec_analyze_report)
	@/bin/cat "$(_altivec_analyze_report)"
	@printf 'Analyzer report: %s\n' "$(_altivec_analyze_report)"

clean:
	@case "$(_altivec_release_dir) $(_altivec_analyze_dir)" in \
		"$(CURDIR)/build-release $(CURDIR)/build-analyze") ;; \
		*) printf '%s\n' 'error: refusing to clean unexpected paths' >&2; \
		   exit 1 ;; \
	esac
	@/bin/rm -rf -- "$(_altivec_release_dir)" "$(_altivec_analyze_dir)"

__altivec_ios_validate:
	@set -eu; \
	case "$(APP_NAME)" in \
		''|.|..|*[!A-Za-z0-9._-]*) \
			printf 'error: invalid APP_NAME: %s\n' "$(APP_NAME)" >&2; \
			exit 1 ;; \
	esac; \
	if [[ "$(ALTIVEC_ARCH)" != armv7 ]]; then \
		printf 'error: this Altivec Toolchain build supports only armv7, not %s\n' \
			"$(ALTIVEC_ARCH)" >&2; \
		exit 1; \
	fi; \
	if [[ -z "$(strip $(SOURCES))" ]]; then \
		printf '%s\n' 'error: SOURCES must contain at least one source file' >&2; \
		exit 1; \
	fi; \
	if [[ -n "$(strip $(_altivec_unsupported_sources))" ]]; then \
		printf 'error: unsupported source file(s): %s\n' \
			"$(_altivec_unsupported_sources)" >&2; \
		printf '%s\n' 'supported suffixes: .c .m .cc .cpp .cxx .mm' >&2; \
		exit 1; \
	fi; \
	for tool in "$(ALTIVEC_CC)" "$(ALTIVEC_CXX)" \
			"$(ALTIVEC_LDID)" "$(ALTIVEC_ZIP)"; do \
		[[ -x "$$tool" ]] || { \
			printf 'error: required Altivec tool is missing: %s\n' "$$tool" >&2; \
			exit 1; \
		}; \
	done; \
	[[ -d "$(SDKROOT)" ]] || { \
		printf 'error: no selected iPhoneOS SDK at %s\n' "$(SDKROOT)" >&2; \
		printf '%s\n' \
			"run 'altivec-sdk install VERSION', then 'altivec-sdk select VERSION'" \
			>&2; \
		exit 1; \
	}; \
	[[ -f "$(SDKROOT)/System/Library/Frameworks/UIKit.framework/Headers/UIKit.h" ]] || { \
		printf 'error: selected SDK is missing UIKit headers: %s\n' \
			"$(SDKROOT)" >&2; \
			exit 1; \
	}; \
	awk -v target="$(IPHONEOS_DEPLOYMENT_TARGET)" \
		'BEGIN { exit((target + 0) >= 5.0 ? 0 : 1) }' || { \
		printf 'error: iOS deployment target must be 5.0 or newer: %s\n' \
			"$(IPHONEOS_DEPLOYMENT_TARGET)" >&2; \
		exit 1; \
	}; \
	[[ -f "$(INFO_PLIST)" ]] || { \
		printf 'error: Info.plist not found: %s\n' "$(INFO_PLIST)" >&2; \
		exit 1; \
	}; \
	for source in $(SOURCES); do \
		[[ -f "$$source" ]] || { \
			printf 'error: source file not found: %s\n' "$$source" >&2; \
			exit 1; \
		}; \
	done; \
	[[ -d "$(APP_PROJECT_ROOT)" ]] || { \
		printf 'error: app project root not found: %s\n' \
			"$(APP_PROJECT_ROOT)" >&2; \
		exit 1; \
	}; \
	project_root="$$(cd "$(APP_PROJECT_ROOT)" && /bin/pwd -P)"; \
	for localization_root in $(BUNDLE_LOCALIZATION_DIRS); do \
		[[ -d "$$localization_root" ]] || { \
			printf 'error: localization root not found: %s\n' \
				"$$localization_root" >&2; \
			exit 1; \
		}; \
		resolved_root="$$(cd "$$localization_root" && /bin/pwd -P)"; \
		case "$$resolved_root" in \
			"$$project_root"|"$$project_root"/*) ;; \
			*) printf 'error: localization root escapes app project: %s\n' \
				"$$localization_root" >&2; \
			   exit 1 ;; \
		esac; \
		found_localization=0; \
		for localization in "$$localization_root"/*.lproj; do \
			[[ -e "$$localization" ]] || continue; \
			[[ -d "$$localization" && ! -L "$$localization" ]] || { \
				printf 'error: localization is not a real directory: %s\n' \
					"$$localization" >&2; \
				exit 1; \
			}; \
			found_localization=1; \
		done; \
		[[ "$$found_localization" == 1 ]] || { \
			printf 'error: localization root has no .lproj directories: %s\n' \
				"$$localization_root" >&2; \
			exit 1; \
		}; \
	done; \
	if [[ -n "$(strip $(ALTIVEC_MANAGED_VERSION))" ]]; then \
		for directory in $(ALTIVEC_MANAGED_INCLUDE_DIRS); do \
			[[ -d "$$directory" ]] || { \
				printf 'error: managed library include directory is missing: %s\n' \
					"$$directory" >&2; \
				exit 1; \
			}; \
		done; \
		for library in $(ALTIVEC_MANAGED_ARCHIVES); do \
			[[ -f "$$library" ]] || { \
				printf 'error: managed static library is missing: %s\n' \
					"$$library" >&2; \
				exit 1; \
			}; \
		done; \
		[[ -d "$(ALTIVEC_MANAGED_BUNDLE_DIR)" ]] || { \
			printf 'error: managed bundle resources are missing: %s\n' \
				"$(ALTIVEC_MANAGED_BUNDLE_DIR)" >&2; \
			exit 1; \
		}; \
		for resource in $(ALTIVEC_MANAGED_RESOURCE_FILES); do \
			[[ -f "$$resource" ]] || { \
				printf 'error: managed bundle resource is missing: %s\n' \
					"$$resource" >&2; \
				exit 1; \
			}; \
		done; \
		for resource in "$(ALTIVEC_MANAGED_BUNDLE_DIR)"/*; do \
			[[ -e "$$resource" ]] || continue; \
			case "$${resource##*/}" in \
				Info.plist|PkgInfo|_CodeSignature|embedded.mobileprovision|"$(APP_NAME)") \
					printf 'error: managed library uses reserved app path: %s\n' \
						"$${resource##*/}" >&2; \
					exit 1 ;; \
			esac; \
		done; \
	fi; \
	for resource in $(RESOURCES); do \
		case "$$resource" in \
			''|/*|.|..|../*|*/../*|*/..|Info.plist|"$(APP_NAME)") \
				printf 'error: unsafe or reserved resource path: %s\n' \
					"$$resource" >&2; \
				exit 1 ;; \
		esac; \
		[[ -e "$(RESOURCE_ROOT)/$$resource" ]] || { \
			printf 'error: resource not found: %s/%s\n' \
				"$(RESOURCE_ROOT)" "$$resource" >&2; \
			exit 1; \
		}; \
	done

$(_altivec_object_dir) $(_altivec_analyze_log_dir):
	@/bin/mkdir -p "$@"

define _altivec_compile_rule
$(call _altivec_object_for,$(1)): $(1) $(_altivec_makefiles) | \
		$(_altivec_object_dir) __altivec_ios_validate
	@printf '[%s] %s\n' \
		$(if $(filter %.m %.mm,$(1)),OBJC,CC) "$(1)"
	@"$(call _altivec_compiler_for,$(1))" \
		$(_altivec_target_flags) \
		$(_altivec_include_flags) \
		$(APP_CPPFLAGS) \
		$(call _altivec_language_flags_for,$(1)) \
		-O2 -DNDEBUG -MMD -MP \
		-c "$$<" -o "$$@"
endef

$(foreach source,$(_altivec_supported_sources),\
	$(eval $(call _altivec_compile_rule,$(source))))

$(_altivec_app_executable): $(_altivec_objects) $(INFO_PLIST) \
		$(_altivec_resource_inputs) $(_altivec_localization_inputs) \
		$(_altivec_managed_inputs) \
		$(_altivec_makefiles) | \
		__altivec_ios_validate
	@printf '[LINK] %s\n' "$(APP_NAME)"
	@if [[ -n "$(strip $(ALTIVEC_MANAGED_VERSION))" ]]; then \
		printf '[LIBS] Altivec %s\n' "$(ALTIVEC_MANAGED_VERSION)"; \
	fi
	@/bin/rm -rf -- "$(_altivec_app_dir)"
	@/bin/mkdir -p "$(_altivec_app_dir)"
	@"$(_altivec_link_driver)" \
		$(_altivec_target_flags) \
		$(_altivec_arc_flag) \
		$(APP_LDFLAGS) \
		-o "$(_altivec_app_executable)" \
		$(foreach object,$(_altivec_objects),"$(object)") \
		$(foreach library,$(ALTIVEC_MANAGED_ARCHIVES),"$(library)") \
		$(_altivec_framework_flags) \
		$(APP_LDLIBS)
	@if [[ -n "$(strip $(ALTIVEC_MANAGED_VERSION))" ]]; then \
		printf '[RESOURCES] Altivec %s\n' "$(ALTIVEC_MANAGED_VERSION)"; \
		/bin/cp -R "$(ALTIVEC_MANAGED_BUNDLE_DIR)/." "$(_altivec_app_dir)/"; \
	fi
	@/bin/cp -f "$(INFO_PLIST)" "$(_altivec_app_dir)/Info.plist"
	@printf 'APPL????' > "$(_altivec_app_dir)/PkgInfo"
	@set -eu; \
	for resource in $(RESOURCES); do \
		source_path="$(RESOURCE_ROOT)/$$resource"; \
		destination_path="$(_altivec_app_dir)/$$resource"; \
		/bin/mkdir -p "$${destination_path%/*}"; \
		if [[ -d "$$source_path" ]]; then \
			/bin/mkdir -p "$$destination_path"; \
			/bin/cp -R "$$source_path/." "$$destination_path/"; \
		else \
			/bin/cp -f "$$source_path" "$$destination_path"; \
		fi; \
	done
	@set -eu; \
	for localization_root in $(BUNDLE_LOCALIZATION_DIRS); do \
		printf '[LOCALIZATIONS] %s\n' "$$localization_root"; \
		for source_path in "$$localization_root"/*.lproj; do \
			[[ -d "$$source_path" ]] || continue; \
			destination_path="$(_altivec_app_dir)/$${source_path##*/}"; \
			/bin/mkdir -p "$$destination_path"; \
			/bin/cp -R "$$source_path/." "$$destination_path/"; \
		done; \
	done
	@printf '[SIGN] %s\n' "$(APP_NAME).app"
	@"$(ALTIVEC_LDID)" -S "$(_altivec_app_executable)"

$(_altivec_ipa_path): $(_altivec_app_executable)
	@printf '[IPA] %s\n' "$(APP_NAME).ipa"
	@/bin/rm -rf -- "$(_altivec_ipa_stage)"
	@/bin/mkdir -p "$(_altivec_ipa_stage)/Payload"
	@/bin/cp -R "$(_altivec_app_dir)" "$(_altivec_ipa_stage)/Payload/"
	@/bin/rm -f -- "$@"
	@cd "$(_altivec_ipa_stage)" && \
		"$(ALTIVEC_ZIP)" -qry "$@" Payload
	@/bin/rm -rf -- "$(_altivec_ipa_stage)"

define _altivec_analyze_rule
$(call _altivec_analyze_log_for,$(1)): $(1) $(_altivec_makefiles) | \
		$(_altivec_analyze_log_dir) __altivec_ios_validate
	@printf '[ANALYZE] %s\n' "$(1)"
	@{ \
		printf '== %s ==\n' "$(1)"; \
		"$(call _altivec_compiler_for,$(1))" \
			$(_altivec_target_flags) \
			$(_altivec_include_flags) \
			$(APP_CPPFLAGS) \
			$(call _altivec_language_flags_for,$(1)) \
			$(APP_ANALYZE_FLAGS) \
			--analyze -Xanalyzer -analyzer-output=text "$(1)"; \
	} > "$$@" 2>&1 || { /bin/cat "$$@"; exit 1; }
endef

$(foreach source,$(_altivec_supported_sources),\
	$(eval $(call _altivec_analyze_rule,$(source))))

$(_altivec_analyze_report): $(_altivec_analyze_logs) \
		$(_altivec_makefiles) | __altivec_ios_validate
	@/bin/mkdir -p "$(@D)"
	@: > "$@"
	@for log in $(_altivec_analyze_logs); do \
		/bin/cat "$$log" >> "$@"; \
	done

-include $(_altivec_objects:.o=.d)

endif
