# Altivec Intelligence Common Makefile for Phone
# Targets: iOS 4.3+ (armv7, arm64)

# --- Tools and Paths ---
CLANG14 = /usr/bin/clang
DSYMUTIL = /usr/bin/dsymutil-14
BIN_DIR = /osxcross/target/bin
IOS_SDK_PATH = /osxcross/target/SDK/iPhoneOS8.4.sdk
# Capture self-dir immediately (:=) so it resolves while this file is still
# $(lastword MAKEFILE_LIST). With ?= alone the RHS is deferred and re-evaluates
# later, after downstream Makefiles include other .mk/.env files — then
# lastword points at those instead and ALTIVEC_ROOT silently mislocates.
_altivec_self_dir := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ALTIVEC_ROOT ?= $(_altivec_self_dir)

# --- Default Build Settings ---
BUILD_DIR ?= build-release
INT_DIR = $(BUILD_DIR)/Intermediates
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
PHONE_IPA = $(BUILD_DIR)/$(APP_NAME).ipa
OPT_FLAGS ?= -O3

# --- Bundle Resources ---
# iPhone bundles have a flat resource root. RES_DIR is a verbatim copy root
# for ordinary resources, including app icons and launch images referenced by
# Info.plist. Use the typed variables below for resources that need explicit
# placement or platform-specific handling.
RES_DIR ?= Resources
# Info.plist lives under RES_DIR but is bundle metadata, so it is copied to
# the app bundle root and skipped by the blind resource copy.
INFO_PLIST ?= $(RES_DIR)/Info.plist
BUNDLE_FONT_DIRS ?=
BUNDLE_LOCALIZATION_DIRS ?=
EXTRA_BUNDLE_STEPS ?=
PHONE_EXTRA_BUNDLE_STEPS ?=

# Optional jailbreak-style pseudo-signing. Set PHONE_LDID_SIGN=1 to sign with
# no entitlements, or set PHONE_LDID_ENTITLEMENTS to sign with an entitlements
# plist. Signing happens before the binary is copied into the app bundle.
PHONE_LDID ?= ldid
PHONE_LDID_SIGN ?= 0
PHONE_LDID_ENTITLEMENTS ?=

PHONE_BUNDLE_DEPS =
ifneq ($(strip $(PHONE_LDID_ENTITLEMENTS)),)
  PHONE_BUNDLE_DEPS += $(PHONE_LDID_ENTITLEMENTS)
endif

# --- Object Mapping ---
include $(ALTIVEC_ROOT)/altivec_common_app.mk
OBJS = $(APP_OBJS)

# --- Auto-detect AltivecCore ---
# iPhone builds link AltivecCore statically. Embedded iOS frameworks require
# iOS 8+ at runtime, so dynamic linkage is intentionally unsupported here.
ALTIVECCORE_LINKAGE ?= static
ifneq ($(strip $(ALTIVECCORE_LINKAGE)),static)
  $(error ALTIVECCORE_LINKAGE=$(ALTIVECCORE_LINKAGE) is not supported for iOS; use static linkage for iOS 4.3-7 compatibility)
endif
ALTIVECCORE_REQUIRED ?= 0
ALTIVECCORE_DIR ?=
ALTIVECCORE_SEARCH_PATHS = $(ALTIVEC_ROOT)/libs/core/build-phone
ifeq ($(strip $(ALTIVECCORE_DIR)),)
  ALTIVECCORE_PATH = $(firstword $(wildcard $(addsuffix /lib/libAltivecCore.a, $(ALTIVECCORE_SEARCH_PATHS))))
  ifneq ($(ALTIVECCORE_PATH),)
    ALTIVECCORE_DIR = $(patsubst %/lib/libAltivecCore.a,%,$(ALTIVECCORE_PATH))
  else ifeq ($(ALTIVECCORE_REQUIRED),1)
    ALTIVECCORE_DIR = $(firstword $(ALTIVECCORE_SEARCH_PATHS))
  endif
endif
ifeq ($(ALTIVECCORE_REQUIRED),1)
  ifneq ($(strip $(ALTIVECCORE_DIR)),)
    EXTRA_FLAGS += -I$(ALTIVECCORE_DIR)/include
  endif
endif

ALTIVECCORE_REQUIRED_FILES = $(ALTIVECCORE_DIR)/lib/libAltivecCore.a \
                             $(ALTIVECCORE_DIR)/lib/cacert.pem \
                             $(ALTIVECCORE_DIR)/include/AltivecCore.h \
                             $(ALTIVECCORE_DIR)/include/sqlite3.h \
                             $(ALTIVECCORE_DIR)/include/cJSON.h
ALTIVECCORE_BOOTSTRAP_PROBE = $(ALTIVECCORE_DIR)/lib/libAltivecCore.a
ALTIVECCORE_BOOTSTRAP_TARGET = phone-static
ALTIVECCORE_BUILD_DIR = build-phone

# --- Auto-detect AltivecCocoa ---
# iPhone builds link AltivecCocoa statically and stage font resources into the
# app bundle. Embedded iOS frameworks are intentionally unsupported here.
ALTIVECCOCOA_LINKAGE ?= static
ifneq ($(strip $(ALTIVECCOCOA_LINKAGE)),static)
  $(error ALTIVECCOCOA_LINKAGE=$(ALTIVECCOCOA_LINKAGE) is not supported for iOS; use static linkage for iOS 4.3-7 compatibility)
endif
ALTIVECCOCOA_REQUIRED ?= 0
ALTIVECCOCOA_DIR ?=
ALTIVECCOCOA_SEARCH_PATHS = $(ALTIVEC_ROOT)/libs/cocoa/build-phone
ifeq ($(strip $(ALTIVECCOCOA_DIR)),)
  ALTIVECCOCOA_PATH = $(firstword $(wildcard $(addsuffix /lib/libAltivecCocoa.a, $(ALTIVECCOCOA_SEARCH_PATHS))))
  ifneq ($(ALTIVECCOCOA_PATH),)
    ALTIVECCOCOA_DIR = $(patsubst %/lib/libAltivecCocoa.a,%,$(ALTIVECCOCOA_PATH))
  else ifeq ($(ALTIVECCOCOA_REQUIRED),1)
    ALTIVECCOCOA_DIR = $(firstword $(ALTIVECCOCOA_SEARCH_PATHS))
  endif
endif
ifeq ($(ALTIVECCOCOA_REQUIRED),1)
  ifneq ($(strip $(ALTIVECCOCOA_DIR)),)
    ALTIVECCOCOA_RESOURCE_DIR = $(ALTIVECCOCOA_DIR)/Resources
    EXTRA_FLAGS += -I$(ALTIVECCOCOA_DIR)/include
  endif
endif

ALTIVECCOCOA_REQUIRED_FILES = $(ALTIVECCOCOA_DIR)/lib/libAltivecCocoa.a \
                              $(ALTIVECCOCOA_DIR)/include/AltivecCocoa.h \
                              $(ALTIVECCOCOA_DIR)/include/AIViewController.h \
                              $(ALTIVECCOCOA_DIR)/include/AICookieCutterWindowController.h \
                              $(ALTIVECCOCOA_DIR)/include/AIWebViewController.h \
                              $(ALTIVECCOCOA_DIR)/include/AIFontAwesome.h \
                              $(ALTIVECCOCOA_DIR)/Resources/Fonts/FA7-Solid-900.otf \
                              $(ALTIVECCOCOA_DIR)/Resources/Fonts/FA7-Regular-400.otf \
                              $(ALTIVECCOCOA_DIR)/Resources/Fonts/FA7-Brands-400.otf \
                              $(ALTIVECCOCOA_DIR)/Resources/Fonts/LICENSE-Font-Awesome.txt
ALTIVECCOCOA_BOOTSTRAP_PROBE = $(ALTIVECCOCOA_DIR)/lib/libAltivecCocoa.a
ALTIVECCOCOA_BOOTSTRAP_TARGET = phone-static
ALTIVECCOCOA_BUILD_DIR = build-phone
ALTIVEC_PLATFORM_TARGET = phone

# --- Flags ---
IOS_FLAGS = $(OPT_FLAGS) $(EXTRA_FLAGS) -g -std=c99 -pedantic -Wall -Wextra -Wconversion -Wsign-conversion -Wfloat-conversion \
            -Wimplicit-function-declaration -Wobjc-method-access \
            -Wno-unused-command-line-argument -Wunguarded-availability -Wno-semicolon-before-method-body \
            -isysroot $(IOS_SDK_PATH) \
            -B$(BIN_DIR)

PHONE_SOURCE_FLAGS ?=
PHONE_EXTRA_SOURCE_FLAGS ?=
PHONE_ANALYZE_SOURCE_FLAGS ?= $(PHONE_SOURCE_FLAGS)
PHONE_ANALYZE_EXTRA_SOURCE_FLAGS ?= $(PHONE_EXTRA_SOURCE_FLAGS)
$(APP_SOURCE_OBJS): IOS_FLAGS += $(PHONE_SOURCE_FLAGS)
$(APP_EXTRA_OBJS): IOS_FLAGS += $(PHONE_EXTRA_SOURCE_FLAGS)

IOS_FRAMEWORKS = -framework UIKit -framework Foundation -framework CoreGraphics
ifeq ($(ALTIVECCORE_REQUIRED),1)
  ifneq ($(strip $(ALTIVECCORE_DIR)),)
    IOS_FRAMEWORKS += $(ALTIVECCORE_DIR)/lib/libAltivecCore.a
  endif
endif
ifeq ($(ALTIVECCOCOA_REQUIRED),1)
  ifneq ($(strip $(ALTIVECCOCOA_DIR)),)
    IOS_FRAMEWORKS += $(ALTIVECCOCOA_DIR)/lib/libAltivecCocoa.a \
                      -framework CoreText
  endif
endif

# --- Top Level Targets ---
.DEFAULT_GOAL := release

release: validate
	@echo "--- Building Phone Release ($(OPT_FLAGS)) ---"
	@$(MAKE) --no-print-directory build-release/$(APP_NAME).ipa BUILD_DIR=build-release OPT_FLAGS=-O3

debug: validate
	@echo "--- Building Phone Debug (-O0) ---"
	@$(MAKE) --no-print-directory build-debug/$(APP_NAME).ipa BUILD_DIR=build-debug OPT_FLAGS=-O0

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf build-release build-debug $(ANALYZE_OUTPUT_DIR)

analyze: validate
	@mkdir -p $(ANALYZE_OUTPUT_DIR)
	@echo "--- Running Clang Static Analyzer (arm64) ---"
	@echo "  > writing report to $(ANALYZE_OUTPUT)"
	$(call analyze_check_sources)
	@: > $(ANALYZE_OUTPUT)
	@if [ -n "$(strip $(ANALYZE_SOURCE_FILES))" ]; then \
		echo "  > analyzing app sources"; \
		$(CLANG14) --analyze -Xanalyzer -analyzer-output=text \
			-target arm64-apple-ios4.3 -arch arm64 -isysroot $(IOS_SDK_PATH) \
			$(IOS_FLAGS) $(PHONE_ANALYZE_SOURCE_FLAGS) \
			$(ANALYZE_SOURCE_FILES) >> $(ANALYZE_OUTPUT) 2>&1 || true; \
	fi
	@if [ -n "$(strip $(ANALYZE_EXTRA_SOURCE_FILES))" ]; then \
		echo "  > analyzing extra sources"; \
		$(CLANG14) --analyze -Xanalyzer -analyzer-output=text \
			-target arm64-apple-ios4.3 -arch arm64 -isysroot $(IOS_SDK_PATH) \
			$(IOS_FLAGS) $(PHONE_ANALYZE_EXTRA_SOURCE_FLAGS) \
			$(ANALYZE_EXTRA_SOURCE_FILES) >> $(ANALYZE_OUTPUT) 2>&1 || true; \
	fi
	$(call analyze_report)

validate: validate-sdk validate-paths libs-ready cocoa-ready

validate-sdk:
	@if [ ! -d "$(IOS_SDK_PATH)" ]; then echo " [!] ERROR: iOS SDK missing at $(IOS_SDK_PATH)"; exit 1; fi

# --- Internal File Targets ---

$(PHONE_IPA): $(APP_BUNDLE)
	@echo " [4/4] Packaging IPA..."
	@rm -rf $(INT_DIR)/Payload
	@mkdir -p $(INT_DIR)/Payload
	@cp -R $(APP_BUNDLE) $(INT_DIR)/Payload/
	@cd $(INT_DIR) && zip -rq ../../$@ Payload
	@rm -rf $(INT_DIR)/Payload

$(APP_BUNDLE): $(INT_DIR)/$(APP_NAME)-bin $(PHONE_BUNDLE_DEPS)
	@echo " [3/4] Building app package..."
	@mkdir -p $@
	@if [ "$(PHONE_LDID_SIGN)" = "1" ] || [ -n "$(PHONE_LDID_ENTITLEMENTS)" ]; then \
		flags="-S" ; \
		if [ -n "$(PHONE_LDID_ENTITLEMENTS)" ]; then flags="-S$(PHONE_LDID_ENTITLEMENTS)" ; fi ; \
		if [ -n "$(PHONE_LDID_ENTITLEMENTS)" ]; then \
			echo "  > ldid-signing $(APP_NAME) with $(PHONE_LDID_ENTITLEMENTS)" ; \
		else \
			echo "  > ldid-signing $(APP_NAME)" ; \
		fi ; \
		$(PHONE_LDID) "$$flags" $< ; \
	fi
	@echo "  > copying binary"
	@cp $< $@/$(APP_NAME)
	@echo "  > copying Info.plist"
	@cp "$(INFO_PLIST)" $@/Info.plist
	$(call copy_bundle_resources,$@)
	$(call copy_bundle_fonts,$@/Fonts)
	$(call copy_bundle_localizations,$@,copy)
	@if [ "$(ALTIVECCORE_REQUIRED)" = "1" ] && [ -f "$(ALTIVECCORE_DIR)/lib/cacert.pem" ]; then \
		echo "  > copying cacert.pem" ; \
		cp "$(ALTIVECCORE_DIR)/lib/cacert.pem" $@/ ; \
	fi
	$(call copy_altiveccocoa_fonts,1,$@/Fonts)
	@echo "  > extracting symbols"
	@$(DSYMUTIL) $< -o $(BUILD_DIR)/$(APP_NAME).dSYM
	@echo -n "APPL????" > $@/PkgInfo
	$(EXTRA_BUNDLE_STEPS)
	$(PHONE_EXTRA_BUNDLE_STEPS)

# Compile and Link in two steps to preserve .o files for dsymutil
$(INT_DIR)/$(APP_NAME)-bin: $(OBJS)
	@echo " [2/4] Linking Phone universal binary (armv7, arm64)..."
	@export PATH=$(BIN_DIR):$(PATH); \
	$(CLANG14) -target arm64-apple-ios4.3 -arch armv7 -arch arm64 \
	           $(IOS_FLAGS) $(IOS_FRAMEWORKS) $(LIBS_IPHONE) $^ -o $@

$(INT_DIR)/%.o: %.m
	@mkdir -p $(INT_DIR)
	@if [ "$(notdir $<)" = "$(firstword $(notdir $(ALL_SOURCES)))" ]; then \
		echo " [1/4] Compiling Files..."; \
	fi
	@echo "  > $(notdir $<)"
	@$(CLANG14) -target arm64-apple-ios4.3 -arch armv7 -arch arm64 \
	           $(IOS_FLAGS) -c $< -o $@

$(INT_DIR)/%.o: %.c
	@mkdir -p $(INT_DIR)
	@if [ "$(notdir $<)" = "$(firstword $(notdir $(ALL_SOURCES)))" ]; then \
		echo " [1/4] Compiling Files..."; \
	fi
	@echo "  > $(notdir $<)"
	@$(CLANG14) -target arm64-apple-ios4.3 -arch armv7 -arch arm64 \
	           $(IOS_FLAGS) -c $< -o $@

.PHONY: release debug clean analyze validate validate-sdk altiveccore-bootstrap libs-ready \
        altiveccocoa-bootstrap cocoa-ready
