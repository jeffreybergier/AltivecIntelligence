# Altivec Intelligence Common Makefile
# This file contains the standard logic for quad-fat mac apps
# Targets: ppc (10.4), x86 (10.4), x64 (10.9), arm (11.0)

# --- Versions ---
SDK_MAC_OLD = 10.5
SDK_MAC_NEW = 11.3
MAC_MIN_OLD = 10.4
MAC_MIN_MID = 10.9
MAC_MIN_NEW = 11.0

# --- Compilers ---
COMPILER_PPC=oppc32-gcc
COMPILER_X86=o32-gcc
COMPILER_X64=/usr/bin/clang
COMPILER_ARM=/usr/bin/clang
DSYMUTIL=/usr/bin/dsymutil-14

# --- SDK Paths ---
SDK_MAC_OLD_PATH=/osxcross/target/SDK/MacOSX$(SDK_MAC_OLD).sdk
SDK_MAC_NEW_PATH=/osxcross/target/SDK/MacOSX$(SDK_MAC_NEW).sdk
LD64_LLD=/osxcross/target/bin/ld64.lld
export OSXCROSS_NO_DSYMUTIL=1

# --- Engine Root ---
# Capture self-dir immediately (:=) so it resolves while this file is still
# $(lastword MAKEFILE_LIST). With ?= alone the RHS is deferred and re-evaluates
# later, after downstream Makefiles include other .mk/.env files — then
# lastword points at those instead and ALTIVEC_ROOT silently mislocates.
_altivec_self_dir := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ALTIVEC_ROOT ?= $(_altivec_self_dir)

# --- Default Build Settings ---
BUILD_DIR ?= build-release
INT_DIR = $(BUILD_DIR)/Intermediates
OPT_FLAGS ?= -O3
UNIVERSAL_BIN ?= $(INT_DIR)/$(APP_NAME)-universal

# --- Flags (Decoupled from SDK) ---
MAC_FLAGS = $(OPT_FLAGS) -g -std=c99 -Wall -Wextra
CLANG_EXTRA_WARNINGS = -Wsign-conversion -Wfloat-conversion -Wno-semicolon-before-method-body
MAC_LIBS = -framework AppKit -lobjc
LEGACY_GCC_FLAGS = -fno-stack-protector -fno-common -fno-zero-initialized-in-bss
MAC_SOURCE_FLAGS ?=
MAC_EXTRA_SOURCE_FLAGS ?=
MAC_ANALYZE_SOURCE_FLAGS ?= $(MAC_SOURCE_FLAGS)
MAC_ANALYZE_EXTRA_SOURCE_FLAGS ?= $(MAC_EXTRA_SOURCE_FLAGS)

# --- Auto-detect AltivecCore ---
# ALTIVECCORE_LINKAGE picks how the core networking stack is linked.
#   dynamic (default): link against AltivecCore.framework; the framework
#                      is copied into <App>.app/Contents/Frameworks/.
#   static           : link the .a archives directly into each slice.
ALTIVECCORE_LINKAGE ?= dynamic
ALTIVECCORE_REQUIRED ?= 0
ALTIVECCORE_DIR ?=
ALTIVECCORE_SEARCH_PATHS = $(ALTIVEC_ROOT)/libs/core/build-mac
ifeq ($(strip $(ALTIVECCORE_DIR)),)
  ALTIVECCORE_PATH = $(firstword $(wildcard $(addsuffix /lib/AltivecCore.framework/AltivecCore, $(ALTIVECCORE_SEARCH_PATHS))))
  ifneq ($(ALTIVECCORE_PATH),)
    ALTIVECCORE_DIR = $(patsubst %/lib/AltivecCore.framework/AltivecCore,%,$(ALTIVECCORE_PATH))
  else ifeq ($(ALTIVECCORE_REQUIRED),1)
    ALTIVECCORE_DIR = $(firstword $(ALTIVECCORE_SEARCH_PATHS))
  endif
endif
ifeq ($(ALTIVECCORE_REQUIRED),1)
  ifneq ($(strip $(ALTIVECCORE_DIR)),)
    ifeq ($(ALTIVECCORE_LINKAGE),dynamic)
      ALTIVECCORE_FRAMEWORK = $(ALTIVECCORE_DIR)/lib/AltivecCore.framework
      MAC_FLAGS += -F$(ALTIVECCORE_DIR)/lib
      MAC_LIBS  += -F$(ALTIVECCORE_DIR)/lib -framework AltivecCore
    else
      MAC_FLAGS += -I$(ALTIVECCORE_DIR)/include
      MAC_LIBS  += -framework SystemConfiguration \
                   $(ALTIVECCORE_DIR)/lib/libAltivecCore.a
    endif
  endif
endif

ifeq ($(ALTIVECCORE_LINKAGE),dynamic)
  ALTIVECCORE_REQUIRED_FILES = $(ALTIVECCORE_DIR)/lib/AltivecCore.framework/AltivecCore \
                               $(ALTIVECCORE_DIR)/lib/AltivecCore.framework/Resources/cacert.pem \
                               $(ALTIVECCORE_DIR)/lib/AltivecCore.framework/Headers/AltivecCore.h \
                               $(ALTIVECCORE_DIR)/lib/AltivecCore.framework/Headers/sqlite3.h \
                               $(ALTIVECCORE_DIR)/lib/AltivecCore.framework/Headers/cJSON.h
  ALTIVECCORE_BOOTSTRAP_PROBE = $(ALTIVECCORE_DIR)/lib/AltivecCore.framework/AltivecCore
  ALTIVECCORE_BOOTSTRAP_TARGET = mac-all
else
  ALTIVECCORE_REQUIRED_FILES = $(ALTIVECCORE_DIR)/lib/libAltivecCore.a \
                               $(ALTIVECCORE_DIR)/lib/cacert.pem \
                               $(ALTIVECCORE_DIR)/include/AltivecCore.h \
                               $(ALTIVECCORE_DIR)/include/sqlite3.h \
                               $(ALTIVECCORE_DIR)/include/cJSON.h
  ALTIVECCORE_BOOTSTRAP_PROBE = $(ALTIVECCORE_DIR)/lib/libAltivecCore.a
  ALTIVECCORE_BOOTSTRAP_TARGET = mac-static
endif
ALTIVECCORE_BUILD_DIR = build-mac

# --- Auto-detect AltivecCocoa ---
# ALTIVECCOCOA_LINKAGE picks how the AppKit compatibility/controller layer is
# linked.
#   dynamic (default): link against AltivecCocoa.framework; the framework is
#                      copied into <App>.app/Contents/Frameworks/.
#   static           : link libAltivecCocoa.a directly into each slice.
ALTIVECCOCOA_LINKAGE ?= dynamic
ALTIVECCOCOA_REQUIRED ?= 0
ALTIVECCOCOA_DIR ?=
ALTIVECCOCOA_SEARCH_PATHS = $(ALTIVEC_ROOT)/libs/cocoa/build-mac
ifeq ($(strip $(ALTIVECCOCOA_DIR)),)
  ALTIVECCOCOA_PATH = $(firstword $(wildcard $(addsuffix /lib/AltivecCocoa.framework/AltivecCocoa, $(ALTIVECCOCOA_SEARCH_PATHS))))
  ifneq ($(ALTIVECCOCOA_PATH),)
    ALTIVECCOCOA_DIR = $(patsubst %/lib/AltivecCocoa.framework/AltivecCocoa,%,$(ALTIVECCOCOA_PATH))
  else ifeq ($(ALTIVECCOCOA_REQUIRED),1)
    ALTIVECCOCOA_DIR = $(firstword $(ALTIVECCOCOA_SEARCH_PATHS))
  endif
endif
ifeq ($(ALTIVECCOCOA_REQUIRED),1)
  ifneq ($(strip $(ALTIVECCOCOA_DIR)),)
    ifeq ($(ALTIVECCOCOA_LINKAGE),dynamic)
      ALTIVECCOCOA_FRAMEWORK = $(ALTIVECCOCOA_DIR)/lib/AltivecCocoa.framework
      MAC_FLAGS += -F$(ALTIVECCOCOA_DIR)/lib
      MAC_LIBS  += -F$(ALTIVECCOCOA_DIR)/lib -framework AltivecCocoa
    else
      ALTIVECCOCOA_RESOURCE_DIR = $(ALTIVECCOCOA_DIR)/Resources
      MAC_FLAGS += -I$(ALTIVECCOCOA_DIR)/include
      MAC_LIBS  += $(ALTIVECCOCOA_DIR)/lib/libAltivecCocoa.a \
                   -framework WebKit \
                   -framework CoreServices \
                   -framework ApplicationServices
    endif
  endif
endif

ifeq ($(ALTIVECCOCOA_LINKAGE),dynamic)
  ALTIVECCOCOA_REQUIRED_FILES = $(ALTIVECCOCOA_DIR)/lib/AltivecCocoa.framework/AltivecCocoa \
                                $(ALTIVECCOCOA_DIR)/lib/AltivecCocoa.framework/Headers/AltivecCocoa.h \
                                $(ALTIVECCOCOA_DIR)/lib/AltivecCocoa.framework/Headers/AIViewController.h \
                                $(ALTIVECCOCOA_DIR)/lib/AltivecCocoa.framework/Headers/AICookieCutterWindowController.h \
                                $(ALTIVECCOCOA_DIR)/lib/AltivecCocoa.framework/Headers/AIWebViewController.h \
                                $(ALTIVECCOCOA_DIR)/lib/AltivecCocoa.framework/Headers/AIFontAwesome.h \
                                $(ALTIVECCOCOA_DIR)/lib/AltivecCocoa.framework/Resources/Fonts/FA7-Solid-900.otf \
                                $(ALTIVECCOCOA_DIR)/lib/AltivecCocoa.framework/Resources/Fonts/FA7-Regular-400.otf \
                                $(ALTIVECCOCOA_DIR)/lib/AltivecCocoa.framework/Resources/Fonts/FA7-Brands-400.otf \
                                $(ALTIVECCOCOA_DIR)/lib/AltivecCocoa.framework/Resources/Fonts/LICENSE-Font-Awesome.txt
  ALTIVECCOCOA_BOOTSTRAP_PROBE = $(ALTIVECCOCOA_DIR)/lib/AltivecCocoa.framework/AltivecCocoa
  ALTIVECCOCOA_BOOTSTRAP_TARGET = mac-all
else
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
  ALTIVECCOCOA_BOOTSTRAP_TARGET = mac-static
endif
ALTIVECCOCOA_BUILD_DIR = build-mac
ALTIVEC_PLATFORM_TARGET = mac

# --- Target Paths ---
BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
ZIP_FILE = $(BUILD_DIR)/$(APP_NAME).zip

# --- Bundle Resources ---
# RES_DIR is a verbatim copy root for ordinary bundle resources. Use the typed
# variables below for resources that need platform-specific placement or
# processing.
RES_DIR ?= Resources
# Info.plist lives under RES_DIR but is bundle metadata, so it is copied to
# Contents/Info.plist and skipped by the blind resource copy.
INFO_PLIST ?= $(RES_DIR)/Info.plist
MAC_ICON ?=
BUNDLE_FONT_DIRS ?=
BUNDLE_LOCALIZATION_DIRS ?=
EXTRA_BUNDLE_STEPS ?=

# --- Object File Mapping ---
include $(ALTIVEC_ROOT)/altivec_common_app.mk

PPC_OBJS = $(call app_objs,$(INT_DIR)/ppc,$(ALL_SOURCES))
X86_OBJS = $(call app_objs,$(INT_DIR)/x86,$(ALL_SOURCES))
X64_OBJS = $(call app_objs,$(INT_DIR)/x64,$(ALL_SOURCES))
ARM_OBJS = $(call app_objs,$(INT_DIR)/arm,$(ALL_SOURCES))

# --- Top Level Targets ---
.DEFAULT_GOAL := release

release: validate
	@echo "--- Building Mac Release (-O3) ---"
	@$(MAKE) --no-print-directory build-release/$(APP_NAME).zip BUILD_DIR=build-release OPT_FLAGS=-O3

debug: validate
	@echo "--- Building Mac Debug (-O0) ---"
	@$(MAKE) --no-print-directory build-debug/$(APP_NAME).zip BUILD_DIR=build-debug OPT_FLAGS=-O0

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf build-release build-debug $(ANALYZE_OUTPUT_DIR)

analyze: validate
	@mkdir -p $(ANALYZE_OUTPUT_DIR)
	@echo "--- Running Clang Static Analyzer (x86_64) ---"
	@echo "  > writing report to $(ANALYZE_OUTPUT)"
	$(call analyze_check_sources)
	@: > $(ANALYZE_OUTPUT)
	@if [ -n "$(strip $(ANALYZE_SOURCE_FILES))" ]; then \
		echo "  > analyzing app sources"; \
		$(COMPILER_X64) --analyze -Xanalyzer -analyzer-output=text \
			-target x86_64-apple-macos$(MAC_MIN_MID) -arch x86_64 -isysroot $(SDK_MAC_NEW_PATH) \
			$(MAC_FLAGS) $(CLANG_EXTRA_WARNINGS) $(MAC_ANALYZE_SOURCE_FLAGS) \
			$(ANALYZE_SOURCE_FILES) >> $(ANALYZE_OUTPUT) 2>&1 || true; \
	fi
	@if [ -n "$(strip $(ANALYZE_EXTRA_SOURCE_FILES))" ]; then \
		echo "  > analyzing extra sources"; \
		$(COMPILER_X64) --analyze -Xanalyzer -analyzer-output=text \
			-target x86_64-apple-macos$(MAC_MIN_MID) -arch x86_64 -isysroot $(SDK_MAC_NEW_PATH) \
			$(MAC_FLAGS) $(CLANG_EXTRA_WARNINGS) $(MAC_ANALYZE_EXTRA_SOURCE_FLAGS) \
			$(ANALYZE_EXTRA_SOURCE_FILES) >> $(ANALYZE_OUTPUT) 2>&1 || true; \
	fi
	$(call analyze_report)

validate: validate-sdk validate-paths libs-ready cocoa-ready

validate-sdk:
	@if [ ! -d "$(SDK_MAC_OLD_PATH)" ]; then echo " [!] ERROR: Mac SDK 10.5 missing at $(SDK_MAC_OLD_PATH)"; exit 1; fi
	@if [ ! -d "$(SDK_MAC_NEW_PATH)" ]; then echo " [!] ERROR: Mac SDK 11.3 missing at $(SDK_MAC_NEW_PATH)"; exit 1; fi

# --- Internal File Targets ---

$(ZIP_FILE): $(BUNDLE)
	@echo " [7/7] Zipping package..."
	@# -y stores framework symlinks as symlinks; without it zip derefs each
	@# link, packing the dylib 3x (root, Versions/Current, Versions/A).
	@cd $(BUILD_DIR) && zip -rqy $(APP_NAME).zip $(APP_NAME).app

$(BUNDLE): $(UNIVERSAL_BIN)
	@echo " [6/7] Building app package..."
	@mkdir -p $@/Contents/MacOS $@/Contents/Resources
	@echo "  > copying binary"
	@cp $< $@/Contents/MacOS/$(APP_NAME)
	@echo "  > copying Info.plist"
	@cp "$(INFO_PLIST)" $@/Contents/Info.plist
	$(call copy_bundle_resources,$@/Contents/Resources)
	@if [ -n "$(MAC_ICON)" ]; then \
		if [ ! -f "$(MAC_ICON)" ]; then echo " [!] ERROR: MAC_ICON not found: $(MAC_ICON)"; exit 1; fi ; \
		echo "  > copying Mac icon" ; \
		cp "$(MAC_ICON)" $@/Contents/Resources/ ; \
	fi
	$(call copy_bundle_fonts,$@/Contents/Resources/Fonts)
	$(call copy_bundle_localizations,$@/Contents/Resources,utf16)
	@if [ "$(ALTIVECCORE_REQUIRED)" = "1" ] && [ "$(ALTIVECCORE_LINKAGE)" = "dynamic" ] && [ -d "$(ALTIVECCORE_FRAMEWORK)" ]; then \
		echo "  > embedding AltivecCore.framework" ; \
		mkdir -p $@/Contents/Frameworks ; \
		cp -RP $(ALTIVECCORE_FRAMEWORK) $@/Contents/Frameworks/ ; \
	fi
	@if [ "$(ALTIVECCOCOA_REQUIRED)" = "1" ] && [ "$(ALTIVECCOCOA_LINKAGE)" = "dynamic" ] && [ -d "$(ALTIVECCOCOA_FRAMEWORK)" ]; then \
		echo "  > embedding AltivecCocoa.framework" ; \
		mkdir -p $@/Contents/Frameworks ; \
		cp -RP $(ALTIVECCOCOA_FRAMEWORK) $@/Contents/Frameworks/ ; \
	fi
	$(call copy_altiveccocoa_fonts,$(if $(filter static,$(ALTIVECCOCOA_LINKAGE)),1,0),$@/Contents/Resources/Fonts)
	@echo "  > extracting symbols (x64, arm)"
	@if [ -f "$(INT_DIR)/x64.bin" ]; then $(DSYMUTIL) $(INT_DIR)/x64.bin -o $(BUILD_DIR)/$(APP_NAME).x64.dSYM; fi
	@if [ -f "$(INT_DIR)/arm.bin" ]; then $(DSYMUTIL) $(INT_DIR)/arm.bin -o $(BUILD_DIR)/$(APP_NAME).arm.dSYM; fi
	@echo -n "APPL????" > $@/Contents/PkgInfo
	$(EXTRA_BUNDLE_STEPS)

$(INT_DIR)/$(APP_NAME)-universal: $(INT_DIR)/ppc.bin $(INT_DIR)/x86.bin $(INT_DIR)/x64.bin $(INT_DIR)/arm.bin
	@echo " [5/7] Merging quad-fat binary (ppc, x86, x64, arm)..."
	@lipo -create $^ -output $@

# --- ppc slice (10.4, 10.5 sdk) ---
$(INT_DIR)/ppc.bin: $(PPC_OBJS)
	@echo "  > linking ppc binary"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_PPC) -arch ppc -isysroot $(SDK_MAC_OLD_PATH) \
	    $^ $(MAC_LIBS) -lgcc_s.10.4 -o $@

$(INT_DIR)/ppc/%.o: %.m
	@mkdir -p $(dir $@)
	@if [ "$(notdir $<)" = "$(firstword $(notdir $(SOURCES)))" ]; then \
		echo " [1/7] Compiling ppc (sdk: $(SDK_MAC_OLD), min: $(MAC_MIN_OLD))..."; \
	fi
	@echo "  > ppc: $(notdir $<)"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_PPC) $(MAC_FLAGS) $(LEGACY_GCC_FLAGS) \
	    -arch ppc -isysroot $(SDK_MAC_OLD_PATH) -c $< -o $@

$(INT_DIR)/ppc/%.o: %.c
	@mkdir -p $(dir $@)
	@echo "  > ppc: $(notdir $<)"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_PPC) $(MAC_FLAGS) $(LEGACY_GCC_FLAGS) \
	    -arch ppc -isysroot $(SDK_MAC_OLD_PATH) -c $< -o $@

# --- x86 slice (10.4, 10.5 sdk) ---
$(INT_DIR)/x86.bin: $(X86_OBJS)
	@echo "  > linking x86 binary"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_X86) -arch i386 -isysroot $(SDK_MAC_OLD_PATH) \
	    $^ $(MAC_LIBS) -lgcc_s.10.4 -o $@

$(INT_DIR)/x86/%.o: %.m
	@mkdir -p $(dir $@)
	@if [ "$(notdir $<)" = "$(firstword $(notdir $(SOURCES)))" ]; then \
		echo " [2/7] Compiling x86 (sdk: $(SDK_MAC_OLD), min: $(MAC_MIN_OLD))..."; \
	fi
	@echo "  > x86: $(notdir $<)"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_X86) $(MAC_FLAGS) $(LEGACY_GCC_FLAGS) \
	    -arch i386 -isysroot $(SDK_MAC_OLD_PATH) -c $< -o $@

$(INT_DIR)/x86/%.o: %.c
	@mkdir -p $(dir $@)
	@echo "  > x86: $(notdir $<)"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_X86) $(MAC_FLAGS) $(LEGACY_GCC_FLAGS) \
	    -arch i386 -isysroot $(SDK_MAC_OLD_PATH) -c $< -o $@

# --- x64 slice (10.9 target, 11.3 sdk) ---
$(INT_DIR)/x64.bin: $(X64_OBJS)
	@echo "  > linking x64 binary"
	@$(COMPILER_X64) -target x86_64-apple-macos$(MAC_MIN_MID) -isysroot $(SDK_MAC_NEW_PATH) \
		-fuse-ld=$(LD64_LLD) -Wl,-platform_version,macos,$(MAC_MIN_MID),$(SDK_MAC_NEW) \
	    $^ $(MAC_LIBS) -o $@

$(INT_DIR)/x64/%.o: %.m
	@mkdir -p $(dir $@)
	@if [ "$(notdir $<)" = "$(firstword $(notdir $(SOURCES)))" ]; then \
		echo " [3/7] Compiling x64 (sdk: $(SDK_MAC_NEW), min: $(MAC_MIN_MID))..."; \
	fi
	@echo "  > x64: $(notdir $<)"
	@$(COMPILER_X64) -target x86_64-apple-macos$(MAC_MIN_MID) -arch x86_64 -isysroot $(SDK_MAC_NEW_PATH) \
	    $(MAC_FLAGS) $(CLANG_EXTRA_WARNINGS) -c $< -o $@

$(INT_DIR)/x64/%.o: %.c
	@mkdir -p $(dir $@)
	@echo "  > x64: $(notdir $<)"
	@$(COMPILER_X64) -target x86_64-apple-macos$(MAC_MIN_MID) -arch x86_64 -isysroot $(SDK_MAC_NEW_PATH) \
	    $(MAC_FLAGS) $(CLANG_EXTRA_WARNINGS) -c $< -o $@

# --- arm slice (11.0 target, 11.3 sdk) ---
$(INT_DIR)/arm.bin: $(ARM_OBJS)
	@echo "  > linking arm64 binary"
	@$(COMPILER_ARM) -target arm64-apple-macos$(MAC_MIN_NEW) -isysroot $(SDK_MAC_NEW_PATH) \
		-fuse-ld=$(LD64_LLD) -Wl,-platform_version,macos,$(MAC_MIN_NEW),$(SDK_MAC_NEW) \
	    $^ $(MAC_LIBS) -o $@

$(INT_DIR)/arm/%.o: %.m
	@mkdir -p $(dir $@)
	@if [ "$(notdir $<)" = "$(firstword $(notdir $(SOURCES)))" ]; then \
		echo " [4/7] Compiling arm64 (sdk: $(SDK_MAC_NEW), min: $(MAC_MIN_NEW))..."; \
	fi
	@echo "  > arm64: $(notdir $<)"
	@$(COMPILER_ARM) -target arm64-apple-macos$(MAC_MIN_NEW) -arch arm64 -isysroot $(SDK_MAC_NEW_PATH) \
	    $(MAC_FLAGS) $(CLANG_EXTRA_WARNINGS) -c $< -o $@

$(INT_DIR)/arm/%.o: %.c
	@mkdir -p $(dir $@)
	@echo "  > arm64: $(notdir $<)"
	@$(COMPILER_ARM) -target arm64-apple-macos$(MAC_MIN_NEW) -arch arm64 -isysroot $(SDK_MAC_NEW_PATH) \
	    $(MAC_FLAGS) $(CLANG_EXTRA_WARNINGS) -c $< -o $@

.PHONY: release debug clean analyze validate validate-sdk altiveccore-bootstrap libs-ready \
        altiveccocoa-bootstrap cocoa-ready
