# Altivec Intelligence Common Makefile
# This file contains the standard logic for Quad-Fat Mac Apps
# Targets: PPC (10.4), X86 (10.4), X64 (10.5), ARM (11.0)

# --- Versions ---
SDK_MAC_MID = 10.5
SDK_MAC_NEW = 11.3
MAC_MIN_PPC = 10.4
MAC_MIN_X86 = 10.4
MAC_MIN_X64 = 10.5
MAC_MIN_ARM = 11.0

# --- Compilers ---
GCC_PPC=oppc32-gcc
GCC_X86=o32-gcc
GCC_X64=o64-gcc
CLANG14=/usr/bin/clang
DSYMUTIL=/usr/bin/dsymutil-14

# --- SDK Paths ---
SDK_MAC_MID_PATH=/osxcross/target/SDK/MacOSX$(SDK_MAC_MID).sdk
SDK_MAC_NEW_PATH=/osxcross/target/SDK/MacOSX$(SDK_MAC_NEW).sdk
SDK_MAC_10_11_PATH=/osxcross/target/SDK/MacOSX10.11.sdk
export OSXCROSS_NO_DSYMUTIL=1

# --- Default Build Settings ---
BUILD_DIR ?= build-release
INT_DIR = $(BUILD_DIR)/Intermediates
OPT_FLAGS ?= -O3
UNIVERSAL_BIN ?= $(INT_DIR)/$(APP_NAME)-universal

# --- Flags (Decoupled from SDK) ---
COMMON_CFLAGS = $(OPT_FLAGS) -g -Wall
MAC_LDFLAGS = -framework AppKit -lobjc

# --- Target Paths ---
BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
ZIP_FILE = $(BUILD_DIR)/$(APP_NAME).zip
RES_DIR ?= Resources
INFO_PLIST ?= Info.plist

# --- Object File Mapping ---
PPC_OBJS = $(addprefix $(INT_DIR)/ppc/, $(SOURCES:.m=.o))
X86_OBJS = $(addprefix $(INT_DIR)/x86/, $(SOURCES:.m=.o))
X64_OBJS = $(addprefix $(INT_DIR)/x64/, $(SOURCES:.m=.o))
ARM_OBJS = $(addprefix $(INT_DIR)/arm/, $(SOURCES:.m=.o))
X64_1011_OBJS = $(addprefix $(INT_DIR)/x64_1011/, $(SOURCES:.m=.o))

# --- Top Level Targets ---

release:
	@echo "--- Building Mac Release (-O3) ---"
	@$(MAKE) --no-print-directory mac BUILD_DIR=build-release OPT_FLAGS=-O3

debug:
	@echo "--- Building Mac Debug (-O0) ---"
	@$(MAKE) --no-print-directory mac BUILD_DIR=build-debug OPT_FLAGS=-O0

teneleven:
	@echo "--- Building Mac 10.11 (x86_64) ---"
	@$(MAKE) --no-print-directory build-teneleven-internal BUILD_DIR=build-10.11 OPT_FLAGS=-O3

build-teneleven-internal:
	@$(MAKE) --no-print-directory $(BUNDLE) UNIVERSAL_BIN=$(INT_DIR)/x64_1011.bin

tenfour:
	@echo "--- Building Mac 10.4 (PPC32) ---"
	@$(MAKE) --no-print-directory build-tenfour-internal BUILD_DIR=build-10.4 OPT_FLAGS=-O3

build-tenfour-internal:
	@$(MAKE) --no-print-directory $(BUNDLE) UNIVERSAL_BIN=$(INT_DIR)/ppc.bin

tenfourintel:
	@echo "--- Building Mac 10.4 (Intel 32) ---"
	@$(MAKE) --no-print-directory build-tenfourintel-internal BUILD_DIR=build-10.4-intel OPT_FLAGS=-O3

build-tenfourintel-internal:
	@$(MAKE) --no-print-directory $(BUNDLE) UNIVERSAL_BIN=$(INT_DIR)/x86.bin

mac: $(ZIP_FILE)

$(ZIP_FILE): $(BUNDLE)
	@echo " [4/4] Zipping package..."
	@cd $(BUILD_DIR) && zip -rq $(APP_NAME).zip $(APP_NAME).app

$(BUNDLE): $(UNIVERSAL_BIN)
	@echo " [3/4] Building app package..."
	@mkdir -p $@/Contents/MacOS $@/Contents/Resources
	@echo "  > copying binary"
	@cp $< $@/Contents/MacOS/$(APP_NAME)
	@echo "  > copying Info.plist"
	@cp $(INFO_PLIST) $@/Contents/Info.plist
	@if [ -d "$(RES_DIR)" ] && [ "$$(ls -A $(RES_DIR) 2>/dev/null)" ]; then \
		echo "  > copying resources" ; \
		cp -R $(RES_DIR)/* $@/Contents/Resources/ ; \
	fi
	@echo "  > extracting symbols"
	@if [ -f "$(INT_DIR)/ppc.bin" ]; then $(DSYMUTIL) $(INT_DIR)/ppc.bin -o $(BUILD_DIR)/$(APP_NAME).PPC.dSYM 2>/dev/null || true; fi
	@if [ -f "$(INT_DIR)/x86.bin" ]; then $(DSYMUTIL) $(INT_DIR)/x86.bin -o $(BUILD_DIR)/$(APP_NAME).X86.dSYM 2>/dev/null || true; fi
	@if [ -f "$(INT_DIR)/x64.bin" ]; then $(DSYMUTIL) $(INT_DIR)/x64.bin -o $(BUILD_DIR)/$(APP_NAME).X64.dSYM; fi
	@if [ -f "$(INT_DIR)/arm.bin" ]; then $(DSYMUTIL) $(INT_DIR)/arm.bin -o $(BUILD_DIR)/$(APP_NAME).ARM.dSYM; fi
	@if [ -f "$(INT_DIR)/x64_1011.bin" ]; then $(DSYMUTIL) $(INT_DIR)/x64_1011.bin -o $(BUILD_DIR)/$(APP_NAME).10.11.dSYM; fi
	@echo -n "APPL????" > $@/Contents/PkgInfo

$(INT_DIR)/$(APP_NAME)-universal: $(INT_DIR)/ppc.bin $(INT_DIR)/x86.bin $(INT_DIR)/x64.bin $(INT_DIR)/arm.bin
	@echo " [2/4] Merging Quad-Fat binary (PPC, X86, X64, ARM)..."
	@lipo -create $^ -output $@

# --- PowerPC Slice ---
$(INT_DIR)/ppc.bin: $(PPC_OBJS)
	@echo "  > linking ppc binary"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_PPC) $(GCC_PPC) -arch ppc -isysroot $(SDK_MAC_MID_PATH) \
	    $(MAC_LDFLAGS) -lgcc_s.10.4 $^ -o $@

$(INT_DIR)/ppc/%.o: %.m
	@mkdir -p $(dir $@)
	@if [ "$(notdir $<)" = "$(firstword $(notdir $(SOURCES)))" ]; then \
		echo " [1/4] Compiling Files..."; \
	fi
	@echo "  > ppc: $(notdir $<)"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_PPC) $(GCC_PPC) $(COMMON_CFLAGS) -arch ppc -isysroot $(SDK_MAC_MID_PATH) \
	    -fno-stack-protector -fno-common -fno-zero-initialized-in-bss -c $< -o $@

# --- Intel X86 Slice ---
$(INT_DIR)/x86.bin: $(X86_OBJS)
	@echo "  > linking x86 binary"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_X86) $(GCC_X86) -arch i386 -isysroot $(SDK_MAC_MID_PATH) \
	    $(MAC_LDFLAGS) $^ -o $@

$(INT_DIR)/x86/%.o: %.m
	@mkdir -p $(dir $@)
	@echo "  > x86: $(notdir $<)"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_X86) $(GCC_X86) $(COMMON_CFLAGS) -arch i386 -isysroot $(SDK_MAC_MID_PATH) \
	    -c $< -o $@

# --- Intel X64 Slice ---
$(INT_DIR)/x64.bin: $(X64_OBJS)
	@echo "  > linking x64 binary"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_X64) $(GCC_X64) -arch x86_64 -isysroot $(SDK_MAC_MID_PATH) \
	    $(MAC_LDFLAGS) $^ -o $@

$(INT_DIR)/x64/%.o: %.m
	@mkdir -p $(dir $@)
	@echo "  > x64: $(notdir $<)"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_X64) $(GCC_X64) $(COMMON_CFLAGS) -arch x86_64 -isysroot $(SDK_MAC_MID_PATH) \
	    -c $< -o $@

# --- Intel X64 (10.11) Slice ---
$(INT_DIR)/x64_1011.bin: $(X64_1011_OBJS)
	@echo "  > linking x86_64 (10.11) binary"
	@MACOSX_DEPLOYMENT_TARGET=10.11 $(CLANG14) -target x86_64-apple-macos10.11 -isysroot $(SDK_MAC_10_11_PATH) \
	    $(MAC_LDFLAGS) -fuse-ld=lld $^ -o $@

$(INT_DIR)/x64_1011/%.o: %.m
	@mkdir -p $(dir $@)
	@if [ "$(notdir $<)" = "$(firstword $(notdir $(SOURCES)))" ]; then \
		echo " [1/4] Compiling Files..."; \
	fi
	@echo "  > x86_64 (10.11): $(notdir $<)"
	@MACOSX_DEPLOYMENT_TARGET=10.11 $(CLANG14) -target x86_64-apple-macos10.11 -isysroot $(SDK_MAC_10_11_PATH) \
	    $(COMMON_CFLAGS) -c $< -o $@

# --- Apple Silicon ARM Slice ---
$(INT_DIR)/arm.bin: $(ARM_OBJS)
	@echo "  > linking arm64 binary"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_ARM) $(CLANG14) -target arm64-apple-macos11 -isysroot $(SDK_MAC_NEW_PATH) \
	    $(MAC_LDFLAGS) -fuse-ld=lld -B/usr/bin/ $^ -o $@

$(INT_DIR)/arm/%.o: %.m
	@mkdir -p $(dir $@)
	@echo "  > arm64: $(notdir $<)"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_ARM) $(CLANG14) -target arm64-apple-macos11 -arch arm64 -isysroot $(SDK_MAC_NEW_PATH) \
	    $(COMMON_CFLAGS) -c $< -o $@

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf build-release build-debug

.PHONY: release debug mac clean
