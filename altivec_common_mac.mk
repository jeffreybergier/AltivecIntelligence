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

# --- Auto-detect libcurl ---
# LIBCURL_LINKAGE picks how libcurl is linked into the app.
#   static  (default): link the five .a archives directly into each slice.
#   dynamic          : link against AltivecCURL.framework; the framework
#                      is copied into <App>.app/Contents/Frameworks/.
LIBCURL_LINKAGE ?= static
LIBCURL_DIR ?=
LIBCURL_SEARCH_PATHS = $(ALTIVEC_ROOT)/libs/libcurl/build-mac
ifeq ($(strip $(LIBCURL_DIR)),)
  LIBCURL_PATH = $(firstword $(wildcard $(addsuffix /lib/libcurl.a, $(LIBCURL_SEARCH_PATHS))))
  ifneq ($(LIBCURL_PATH),)
    LIBCURL_DIR = $(patsubst %/lib/libcurl.a,%,$(LIBCURL_PATH))
  endif
endif
ifneq ($(strip $(LIBCURL_DIR)),)
  ifeq ($(LIBCURL_LINKAGE),dynamic)
    LIBCURL_FRAMEWORK = $(LIBCURL_DIR)/lib/AltivecCURL.framework
    MAC_FLAGS += -F$(LIBCURL_DIR)/lib
    MAC_LIBS  += -F$(LIBCURL_DIR)/lib -framework AltivecCURL
  else
    MAC_FLAGS += -I$(LIBCURL_DIR)/include
    MAC_LIBS  += -framework SystemConfiguration \
                 $(LIBCURL_DIR)/lib/libAICURLConnection.a \
                 $(LIBCURL_DIR)/lib/libcurl.a \
                 $(LIBCURL_DIR)/lib/libssl.a \
                 $(LIBCURL_DIR)/lib/libcrypto.a \
                 $(LIBCURL_DIR)/lib/libz.a
  endif
endif

# --- Optional libcurl hard requirements ---
LIBCURL_REQUIRED ?= 0
ifeq ($(LIBCURL_LINKAGE),dynamic)
  LIBCURL_REQUIRED_FILES = $(LIBCURL_DIR)/lib/AltivecCURL.framework/AltivecCURL \
                           $(LIBCURL_DIR)/lib/AltivecCURL.framework/Resources/cacert.pem
else
  LIBCURL_REQUIRED_FILES = $(LIBCURL_DIR)/lib/libAICURLConnection.a \
                           $(LIBCURL_DIR)/lib/libcurl.a \
                           $(LIBCURL_DIR)/lib/libssl.a \
                           $(LIBCURL_DIR)/lib/libcrypto.a \
                           $(LIBCURL_DIR)/lib/libz.a \
                           $(LIBCURL_DIR)/lib/cacert.pem
endif

# --- Target Paths ---
BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
ZIP_FILE = $(BUILD_DIR)/$(APP_NAME).zip
RES_DIR ?= Resources
INFO_PLIST ?= Info.plist

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
	@rm -rf build-release build-debug

analyze: validate
	@echo "--- Running Clang Static Analyzer (x86_64) ---"
	@$(COMPILER_X64) --analyze -Xanalyzer -analyzer-output=text \
		-target x86_64-apple-macos$(MAC_MIN_MID) -arch x86_64 -isysroot $(SDK_MAC_NEW_PATH) \
		$(MAC_FLAGS) $(CLANG_EXTRA_WARNINGS) $(ALL_SOURCES)

validate:
	@if [ ! -d "$(SDK_MAC_OLD_PATH)" ]; then echo " [!] ERROR: Mac SDK 10.5 missing at $(SDK_MAC_OLD_PATH)"; exit 1; fi
	@if [ ! -d "$(SDK_MAC_NEW_PATH)" ]; then echo " [!] ERROR: Mac SDK 11.3 missing at $(SDK_MAC_NEW_PATH)"; exit 1; fi
	@if [ "$(LIBCURL_REQUIRED)" = "1" ]; then $(MAKE) --no-print-directory libcurl-bootstrap; fi
	@if [ "$(LIBCURL_REQUIRED)" = "1" ]; then $(MAKE) --no-print-directory libs-ready; fi
	@for dir in $(patsubst -I%,%,$(filter -I%,$(MAC_FLAGS))) $(patsubst -L%,%,$(filter -L%,$(MAC_LIBS))); do \
		if [ ! -d "$$dir" ]; then \
			echo " [!] ERROR: Dependency directory missing: $$dir"; \
			echo "     This likely means a required library (like libcurl) hasn't been built."; \
			exit 1; \
		fi; \
	done

libcurl-bootstrap:
	@if [ "$(LIBCURL_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(LIBCURL_DIR)" ]; then \
		echo " [!] ERROR: libcurl is required but LIBCURL_DIR is not set or auto-detected."; \
		echo "     Set LIBCURL_DIR=/path/to/libs/libcurl/build-mac or build at $(ALTIVEC_ROOT)/libs/libcurl/build-mac."; \
		exit 1; \
	fi
	@probe="$(LIBCURL_DIR)/lib/libcurl.a"; target=mac-static; \
	if [ "$(LIBCURL_LINKAGE)" = "dynamic" ]; then \
		probe="$(LIBCURL_DIR)/lib/AltivecCURL.framework/AltivecCURL"; target=mac-all; \
	fi; \
	if [ ! -e "$$probe" ]; then \
		echo " [!] Missing libcurl artifact ($$probe), running bootstrap build ($$target)..."; \
		$(MAKE) -C $(ALTIVEC_ROOT)/libs/libcurl $$target; \
	fi

libs-ready:
	@if [ "$(LIBCURL_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(LIBCURL_DIR)" ]; then \
		echo " [!] ERROR: libcurl is required but LIBCURL_DIR is not set or auto-detected."; \
		echo "     Set LIBCURL_DIR=/path/to/libs/libcurl/build-mac."; \
		exit 1; \
	fi
	@missing=""; \
	for f in $(LIBCURL_REQUIRED_FILES); do \
		if [ ! -f "$$f" ]; then missing="$$missing $$f"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo " [!] ERROR: Missing required libcurl artifacts:$$missing"; \
		echo "     Build them with: make -C $(ALTIVEC_ROOT)/libs/libcurl mac-static"; \
		exit 1; \
	fi

# --- Internal File Targets ---

$(ZIP_FILE): $(BUNDLE)
	@echo " [7/7] Zipping package..."
	@cd $(BUILD_DIR) && zip -rq $(APP_NAME).zip $(APP_NAME).app

$(BUNDLE): $(UNIVERSAL_BIN)
	@echo " [6/7] Building app package..."
	@mkdir -p $@/Contents/MacOS $@/Contents/Resources
	@echo "  > copying binary"
	@cp $< $@/Contents/MacOS/$(APP_NAME)
	@echo "  > copying Info.plist"
	@cp $(INFO_PLIST) $@/Contents/Info.plist
	@if [ -d "$(RES_DIR)" ] && [ "$$(ls -A $(RES_DIR) 2>/dev/null)" ]; then \
		echo "  > copying resources" ; \
		cp -R $(RES_DIR)/* $@/Contents/Resources/ ; \
	fi
	@if [ "$(LIBCURL_LINKAGE)" = "dynamic" ] && [ -d "$(LIBCURL_FRAMEWORK)" ]; then \
		echo "  > embedding AltivecCURL.framework" ; \
		mkdir -p $@/Contents/Frameworks ; \
		cp -RP $(LIBCURL_FRAMEWORK) $@/Contents/Frameworks/ ; \
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

.PHONY: release debug clean analyze validate libcurl-bootstrap libs-ready
