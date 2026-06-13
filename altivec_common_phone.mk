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
# Support both .m and .c files in SOURCES and EXTRA_SOURCES
ALL_SOURCES = $(SOURCES) $(EXTRA_SOURCES)
OBJS = $(addprefix $(INT_DIR)/, $(filter %.o, $(SOURCES:.m=.o) $(SOURCES:.c=.o) $(EXTRA_SOURCES:.m=.o) $(EXTRA_SOURCES:.c=.o)))

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

# --- Flags ---
IOS_FLAGS = $(OPT_FLAGS) $(EXTRA_FLAGS) -g -std=c99 -pedantic -Wall -Wextra -Wconversion -Wsign-conversion -Wfloat-conversion \
            -Wimplicit-function-declaration -Wobjc-method-access \
            -Wno-unused-command-line-argument -Wunguarded-availability -Wno-semicolon-before-method-body \
            -isysroot $(IOS_SDK_PATH) \
            -B$(BIN_DIR)

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

# --- Static analyzer ---
# Local Makefiles set ANALYZE_DIRS to the same dirs they vpath sources from,
# so basenames like 'foo.c' resolve to a real path. vpath rewrites
# prerequisite lookups for make rules but does NOT rewrite a recipe's argv,
# so the analyzer (which we invoke directly on source files, not via the
# pattern rules) needs its own resolution step.
ANALYZE_DIRS       ?= .
ANALYZE_OUTPUT_DIR ?= build-analyze
ANALYZE_OUTPUT     ?= $(ANALYZE_OUTPUT_DIR)/analyze.txt
analyze_find        = $(firstword $(foreach d,$(ANALYZE_DIRS),$(wildcard $(d)/$(1))))
ANALYZE_SOURCES     = $(foreach s,$(ALL_SOURCES),$(call analyze_find,$(s)))

analyze: validate
	@mkdir -p $(ANALYZE_OUTPUT_DIR)
	@echo "--- Running Clang Static Analyzer (arm64) ---"
	@echo "  > writing report to $(ANALYZE_OUTPUT)"
	@$(CLANG14) --analyze -Xanalyzer -analyzer-output=text \
		-target arm64-apple-ios4.3 -arch arm64 -isysroot $(IOS_SDK_PATH) \
		$(IOS_FLAGS) $(ANALYZE_SOURCES) > $(ANALYZE_OUTPUT) 2>&1 || true
	@warnings=$$(grep -cE '^.+:[0-9]+:[0-9]+: warning:' $(ANALYZE_OUTPUT) 2>/dev/null || true); \
	errors=$$(grep -cE '^.+:[0-9]+:[0-9]+: error:' $(ANALYZE_OUTPUT) 2>/dev/null || true); \
	echo "  > $${warnings:-0} warning(s), $${errors:-0} error(s) — see $(ANALYZE_OUTPUT)"

# Directories the local Makefile wants validated before a build/analyze runs.
# Mirrors ANALYZE_DIRS in shape: a positive list, only what's explicitly given
# gets checked. Dep dirs (cJSON, qrcodegen, libcurl headers, etc.) are
# intentionally NOT included by default — those are managed by their own
# build systems and have their own bootstrap targets.
VALIDATE_PATHS ?=

validate:
	@if [ ! -d "$(IOS_SDK_PATH)" ]; then echo " [!] ERROR: iOS SDK missing at $(IOS_SDK_PATH)"; exit 1; fi
	@if [ "$(ALTIVECCORE_REQUIRED)" = "1" ]; then $(MAKE) --no-print-directory altiveccore-bootstrap; fi
	@if [ "$(ALTIVECCORE_REQUIRED)" = "1" ]; then $(MAKE) --no-print-directory libs-ready; fi
	@if [ "$(ALTIVECCOCOA_REQUIRED)" = "1" ]; then $(MAKE) --no-print-directory altiveccocoa-bootstrap; fi
	@if [ "$(ALTIVECCOCOA_REQUIRED)" = "1" ]; then $(MAKE) --no-print-directory cocoa-ready; fi
	@for dir in $(VALIDATE_PATHS); do \
		if [ ! -d "$$dir" ]; then \
			echo " [!] ERROR: Project directory missing: $$dir"; \
			exit 1; \
		fi; \
	done

altiveccore-bootstrap:
	@if [ "$(ALTIVECCORE_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(ALTIVECCORE_DIR)" ]; then \
		echo " [!] ERROR: AltivecCore is required but ALTIVECCORE_DIR is not set."; \
		echo "     Set ALTIVECCORE_DIR=/path/to/libs/core/build-phone or build at $(ALTIVEC_ROOT)/libs/core/build-phone."; \
		exit 1; \
	fi
	@probe="$(ALTIVECCORE_DIR)/lib/libAltivecCore.a"; target=phone-static; \
	if [ ! -e "$$probe" ]; then \
		echo " [!] Missing AltivecCore artifact ($$probe), running bootstrap build ($$target)..."; \
		$(MAKE) -C $(ALTIVEC_ROOT)/libs/core $$target; \
	fi

libs-ready:
	@if [ "$(ALTIVECCORE_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(ALTIVECCORE_DIR)" ]; then \
		echo " [!] ERROR: AltivecCore is required but ALTIVECCORE_DIR is not set."; \
		echo "     Set ALTIVECCORE_DIR=/path/to/libs/core/build-phone."; \
		exit 1; \
	fi
	@missing=""; \
	for f in $(ALTIVECCORE_REQUIRED_FILES); do \
		if [ ! -f "$$f" ]; then missing="$$missing $$f"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo " [!] ERROR: Missing required AltivecCore artifacts:$$missing"; \
		echo "     Build them with: make -C $(ALTIVEC_ROOT)/libs/core phone"; \
		exit 1; \
	fi

altiveccocoa-bootstrap:
	@if [ "$(ALTIVECCOCOA_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(ALTIVECCOCOA_DIR)" ]; then \
		echo " [!] ERROR: AltivecCocoa is required but ALTIVECCOCOA_DIR is not set."; \
		echo "     Set ALTIVECCOCOA_DIR=/path/to/libs/cocoa/build-phone or build at $(ALTIVEC_ROOT)/libs/cocoa/build-phone."; \
		exit 1; \
	fi
	@probe="$(ALTIVECCOCOA_DIR)/lib/libAltivecCocoa.a"; target=phone-static; \
	if [ ! -e "$$probe" ]; then \
		echo " [!] Missing AltivecCocoa artifact ($$probe), running bootstrap build ($$target)..."; \
		$(MAKE) -C $(ALTIVEC_ROOT)/libs/cocoa $$target; \
	fi

cocoa-ready:
	@if [ "$(ALTIVECCOCOA_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(ALTIVECCOCOA_DIR)" ]; then \
		echo " [!] ERROR: AltivecCocoa is required but ALTIVECCOCOA_DIR is not set."; \
		echo "     Set ALTIVECCOCOA_DIR=/path/to/libs/cocoa/build-phone."; \
		exit 1; \
	fi
	@missing=""; \
	for f in $(ALTIVECCOCOA_REQUIRED_FILES); do \
		if [ ! -f "$$f" ]; then missing="$$missing $$f"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo " [!] ERROR: Missing required AltivecCocoa artifacts:$$missing"; \
		echo "     Build them with: make -C $(ALTIVEC_ROOT)/libs/cocoa phone"; \
		exit 1; \
	fi

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
	@if [ -d "$(RES_DIR)" ]; then \
		did_copy=0 ; \
		for res in "$(RES_DIR)"/*; do \
			[ -e "$$res" ] || continue ; \
			[ "$$(basename "$$res")" = "Info.plist" ] && continue ; \
			if [ "$$did_copy" = "0" ]; then echo "  > copying resources" ; did_copy=1 ; fi ; \
			cp -R "$$res" $@/ ; \
		done ; \
	fi
	@for dir in $(BUNDLE_FONT_DIRS); do \
		if [ -d "$$dir" ] && [ "$$(ls -A "$$dir" 2>/dev/null)" ]; then \
			echo "  > copying fonts from $$dir" ; \
			mkdir -p $@/Fonts ; \
			cp -R "$$dir"/* $@/Fonts/ ; \
		fi ; \
	done
	@for dir in $(BUNDLE_LOCALIZATION_DIRS); do \
		if ls "$$dir"/*.lproj >/dev/null 2>&1; then \
			echo "  > copying localizations from $$dir" ; \
			for lproj in "$$dir"/*.lproj; do \
				[ -d "$$lproj" ] || continue ; \
				cp -R "$$lproj" $@/ ; \
			done ; \
		fi ; \
	done
	@if [ "$(ALTIVECCORE_REQUIRED)" = "1" ] && [ -f "$(ALTIVECCORE_DIR)/lib/cacert.pem" ]; then \
		echo "  > copying cacert.pem" ; \
		cp "$(ALTIVECCORE_DIR)/lib/cacert.pem" $@/ ; \
	fi
	@if [ "$(ALTIVECCOCOA_REQUIRED)" = "1" ] && [ -d "$(ALTIVECCOCOA_RESOURCE_DIR)/Fonts" ]; then \
		echo "  > copying AltivecCocoa fonts" ; \
		mkdir -p $@/Fonts ; \
		cp "$(ALTIVECCOCOA_RESOURCE_DIR)"/Fonts/*.otf $@/Fonts/ ; \
		cp "$(ALTIVECCOCOA_RESOURCE_DIR)"/Fonts/LICENSE-Font-Awesome.txt $@/Fonts/ ; \
	fi
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

.PHONY: release debug clean analyze validate altiveccore-bootstrap libs-ready \
        altiveccocoa-bootstrap cocoa-ready
