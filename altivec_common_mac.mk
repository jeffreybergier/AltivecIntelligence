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
                   $(ALTIVECCORE_DIR)/lib/libAICURLConnection.a \
                   $(ALTIVECCORE_DIR)/lib/libcurl.a \
                   $(ALTIVECCORE_DIR)/lib/libssl.a \
                   $(ALTIVECCORE_DIR)/lib/libcrypto.a \
                   $(ALTIVECCORE_DIR)/lib/libz.a \
                   $(ALTIVECCORE_DIR)/lib/libsqlite3.a \
                   $(ALTIVECCORE_DIR)/lib/libcjson.a
    endif
  endif
endif

ifeq ($(ALTIVECCORE_LINKAGE),dynamic)
  ALTIVECCORE_REQUIRED_FILES = $(ALTIVECCORE_DIR)/lib/AltivecCore.framework/AltivecCore \
                               $(ALTIVECCORE_DIR)/lib/AltivecCore.framework/Resources/cacert.pem \
                               $(ALTIVECCORE_DIR)/lib/AltivecCore.framework/Headers/AltivecCore.h \
                               $(ALTIVECCORE_DIR)/lib/AltivecCore.framework/Headers/sqlite3.h \
                               $(ALTIVECCORE_DIR)/lib/AltivecCore.framework/Headers/cJSON.h
else
  ALTIVECCORE_REQUIRED_FILES = $(ALTIVECCORE_DIR)/lib/libAICURLConnection.a \
                               $(ALTIVECCORE_DIR)/lib/libcurl.a \
                               $(ALTIVECCORE_DIR)/lib/libssl.a \
                               $(ALTIVECCORE_DIR)/lib/libcrypto.a \
                               $(ALTIVECCORE_DIR)/lib/libz.a \
                               $(ALTIVECCORE_DIR)/lib/libsqlite3.a \
                               $(ALTIVECCORE_DIR)/lib/libcjson.a \
                               $(ALTIVECCORE_DIR)/lib/cacert.pem \
                               $(ALTIVECCORE_DIR)/include/AltivecCore.h \
                               $(ALTIVECCORE_DIR)/include/sqlite3.h \
                               $(ALTIVECCORE_DIR)/include/cJSON.h
endif

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
endif

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
# Support both .m and .c files in SOURCES and EXTRA_SOURCES
ALL_SOURCES = $(SOURCES) $(EXTRA_SOURCES)
# Function to map sources to objects in a specific directory
map_objs = $(addprefix $(1)/, $(filter %.o, $(SOURCES:.m=.o) $(SOURCES:.c=.o) $(EXTRA_SOURCES:.m=.o) $(EXTRA_SOURCES:.c=.o)))

PPC_OBJS = $(call map_objs, $(INT_DIR)/ppc)
X86_OBJS = $(call map_objs, $(INT_DIR)/x86)
X64_OBJS = $(call map_objs, $(INT_DIR)/x64)
ARM_OBJS = $(call map_objs, $(INT_DIR)/arm)

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
	@echo "--- Running Clang Static Analyzer (x86_64) ---"
	@echo "  > writing report to $(ANALYZE_OUTPUT)"
	@$(COMPILER_X64) --analyze -Xanalyzer -analyzer-output=text \
		-target x86_64-apple-macos$(MAC_MIN_MID) -arch x86_64 -isysroot $(SDK_MAC_NEW_PATH) \
		$(MAC_FLAGS) $(CLANG_EXTRA_WARNINGS) $(ANALYZE_SOURCES) > $(ANALYZE_OUTPUT) 2>&1 || true
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
	@if [ ! -d "$(SDK_MAC_OLD_PATH)" ]; then echo " [!] ERROR: Mac SDK 10.5 missing at $(SDK_MAC_OLD_PATH)"; exit 1; fi
	@if [ ! -d "$(SDK_MAC_NEW_PATH)" ]; then echo " [!] ERROR: Mac SDK 11.3 missing at $(SDK_MAC_NEW_PATH)"; exit 1; fi
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
		echo "     Set ALTIVECCORE_DIR=/path/to/libs/core/build-mac or build at $(ALTIVEC_ROOT)/libs/core/build-mac."; \
		exit 1; \
	fi
	@probe="$(ALTIVECCORE_DIR)/lib/libcjson.a"; target=mac-static; \
	if [ "$(ALTIVECCORE_LINKAGE)" = "dynamic" ]; then \
		probe="$(ALTIVECCORE_DIR)/lib/AltivecCore.framework/AltivecCore"; target=mac-all; \
	fi; \
	if [ ! -e "$$probe" ]; then \
		echo " [!] Missing AltivecCore artifact ($$probe), running bootstrap build ($$target)..."; \
		$(MAKE) -C $(ALTIVEC_ROOT)/libs/core $$target; \
	fi

libs-ready:
	@if [ "$(ALTIVECCORE_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(ALTIVECCORE_DIR)" ]; then \
		echo " [!] ERROR: AltivecCore is required but ALTIVECCORE_DIR is not set."; \
		echo "     Set ALTIVECCORE_DIR=/path/to/libs/core/build-mac."; \
		exit 1; \
	fi
	@missing=""; \
	for f in $(ALTIVECCORE_REQUIRED_FILES); do \
		if [ ! -f "$$f" ]; then missing="$$missing $$f"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo " [!] ERROR: Missing required AltivecCore artifacts:$$missing"; \
		echo "     Build them with: make -C $(ALTIVEC_ROOT)/libs/core mac"; \
		exit 1; \
	fi

altiveccocoa-bootstrap:
	@if [ "$(ALTIVECCOCOA_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(ALTIVECCOCOA_DIR)" ]; then \
		echo " [!] ERROR: AltivecCocoa is required but ALTIVECCOCOA_DIR is not set."; \
		echo "     Set ALTIVECCOCOA_DIR=/path/to/libs/cocoa/build-mac or build at $(ALTIVEC_ROOT)/libs/cocoa/build-mac."; \
		exit 1; \
	fi
	@probe="$(ALTIVECCOCOA_DIR)/lib/libAltivecCocoa.a"; target=mac-static; \
	if [ "$(ALTIVECCOCOA_LINKAGE)" = "dynamic" ]; then \
		probe="$(ALTIVECCOCOA_DIR)/lib/AltivecCocoa.framework/AltivecCocoa"; target=mac-all; \
	fi; \
	if [ ! -e "$$probe" ]; then \
		echo " [!] Missing AltivecCocoa artifact ($$probe), running bootstrap build ($$target)..."; \
		$(MAKE) -C $(ALTIVEC_ROOT)/libs/cocoa $$target; \
	fi

cocoa-ready:
	@if [ "$(ALTIVECCOCOA_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(ALTIVECCOCOA_DIR)" ]; then \
		echo " [!] ERROR: AltivecCocoa is required but ALTIVECCOCOA_DIR is not set."; \
		echo "     Set ALTIVECCOCOA_DIR=/path/to/libs/cocoa/build-mac."; \
		exit 1; \
	fi
	@missing=""; \
	for f in $(ALTIVECCOCOA_REQUIRED_FILES); do \
		if [ ! -f "$$f" ]; then missing="$$missing $$f"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo " [!] ERROR: Missing required AltivecCocoa artifacts:$$missing"; \
		echo "     Build them with: make -C $(ALTIVEC_ROOT)/libs/cocoa mac"; \
		exit 1; \
	fi

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
	@if [ -d "$(RES_DIR)" ]; then \
		did_copy=0 ; \
		for res in "$(RES_DIR)"/*; do \
			[ -e "$$res" ] || continue ; \
			[ "$$(basename "$$res")" = "Info.plist" ] && continue ; \
			if [ "$$did_copy" = "0" ]; then echo "  > copying resources" ; did_copy=1 ; fi ; \
			cp -R "$$res" $@/Contents/Resources/ ; \
		done ; \
	fi
	@if [ -n "$(MAC_ICON)" ]; then \
		if [ ! -f "$(MAC_ICON)" ]; then echo " [!] ERROR: MAC_ICON not found: $(MAC_ICON)"; exit 1; fi ; \
		echo "  > copying Mac icon" ; \
		cp "$(MAC_ICON)" $@/Contents/Resources/ ; \
	fi
	@for dir in $(BUNDLE_FONT_DIRS); do \
		if [ -d "$$dir" ] && [ "$$(ls -A "$$dir" 2>/dev/null)" ]; then \
			echo "  > copying fonts from $$dir" ; \
			mkdir -p $@/Contents/Resources/Fonts ; \
			cp -R "$$dir"/* $@/Contents/Resources/Fonts/ ; \
		fi ; \
	done
	@for dir in $(BUNDLE_LOCALIZATION_DIRS); do \
		if ls "$$dir"/*.lproj >/dev/null 2>&1; then \
			echo "  > copying localizations from $$dir" ; \
			for lproj in "$$dir"/*.lproj; do \
				[ -d "$$lproj" ] || continue ; \
				cp -R "$$lproj" $@/Contents/Resources/ ; \
				for strings in "$$lproj"/*.strings; do \
					[ -f "$$strings" ] || continue ; \
					dest="$@/Contents/Resources/$$(basename "$$lproj")/$$(basename "$$strings")" ; \
					tmp="$$dest.utf16" ; \
					echo "  > transcoding $$(basename "$$lproj")/$$(basename "$$strings") to UTF-16 LE" ; \
					printf '\377\376' > "$$tmp" ; \
					iconv -f UTF-8 -t UTF-16LE "$$strings" >> "$$tmp" ; \
					mv "$$tmp" "$$dest" ; \
				done ; \
			done ; \
		fi ; \
	done
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
	@if [ "$(ALTIVECCOCOA_REQUIRED)" = "1" ] && [ "$(ALTIVECCOCOA_LINKAGE)" = "static" ] && [ -d "$(ALTIVECCOCOA_RESOURCE_DIR)/Fonts" ]; then \
		echo "  > copying AltivecCocoa fonts" ; \
		mkdir -p $@/Contents/Resources/Fonts ; \
		cp "$(ALTIVECCOCOA_RESOURCE_DIR)"/Fonts/*.otf $@/Contents/Resources/Fonts/ ; \
		cp "$(ALTIVECCOCOA_RESOURCE_DIR)"/Fonts/LICENSE-Font-Awesome.txt $@/Contents/Resources/Fonts/ ; \
	fi
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

.PHONY: release debug clean analyze validate altiveccore-bootstrap libs-ready \
        altiveccocoa-bootstrap cocoa-ready
