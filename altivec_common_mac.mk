# Altivec Intelligence Common Makefile
# This file contains the standard logic for Quad-Fat Mac Apps
# Targets: PPC (10.4), X86 (10.4), X64 (10.5), ARM (11.0)

# --- Versions ---
SDK_MAC_MID = 10.6
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
export OSXCROSS_NO_DSYMUTIL=1

# --- Default Build Settings ---
BUILD_DIR ?= build-release
INT_DIR = $(BUILD_DIR)/Intermediates
OPT_FLAGS ?= -O3

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

# --- Top Level Targets ---

release:
	@echo "--- Building Mac Release (-O3) ---"
	@$(MAKE) --no-print-directory mac BUILD_DIR=build-release OPT_FLAGS=-O3

debug:
	@echo "--- Building Mac Debug (-O0) ---"
	@$(MAKE) --no-print-directory mac BUILD_DIR=build-debug OPT_FLAGS=-O0

mac: $(ZIP_FILE)

$(ZIP_FILE): $(BUNDLE)
	@echo "[4/4] Zipping package..."
	@cd $(BUILD_DIR) && zip -rq $(APP_NAME).zip $(APP_NAME).app

$(BUNDLE): $(INT_DIR)/$(APP_NAME)-universal
	@echo "[3/4] Building app package..."
	@mkdir -p $@/Contents/MacOS $@/Contents/Resources
	# Copy binary
	@cp $< $@/Contents/MacOS/$(APP_NAME)
	# Copy Info.plist (Special handling)
	@cp $(INFO_PLIST) $@/Contents/Info.plist
	# Blind Copy all other resources into Contents/Resources/
	@if [ -d "$(RES_DIR)" ] && [ "$$(ls -A $(RES_DIR) 2>/dev/null)" ]; then \
		cp -R $(RES_DIR)/* $@/Contents/Resources/ ; \
	fi
	# Extract symbols for modern targets (X64 and ARM)
	@echo "Extracting symbols..."
	@$(DSYMUTIL) $(INT_DIR)/x64.bin -o $(BUILD_DIR)/$(APP_NAME).X64.dSYM
	@$(DSYMUTIL) $(INT_DIR)/arm64.bin -o $(BUILD_DIR)/$(APP_NAME).ARM.dSYM
	@echo -n "APPL????" > $@/Contents/PkgInfo

$(INT_DIR)/$(APP_NAME)-universal: $(INT_DIR)/ppc.bin $(INT_DIR)/x86.bin $(INT_DIR)/x64.bin $(INT_DIR)/arm64.bin
	@echo "[2/4] Merging Quad-Fat binary (PPC, X86, X64, ARM)..."
	@lipo -create $^ -output $@

# --- PowerPC Slice ---
$(INT_DIR)/ppc.bin: $(PPC_OBJS)
	@echo " > ppc (sdk:$(SDK_MAC_MID), min:$(MAC_MIN_PPC))"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_PPC) $(GCC_PPC) -arch ppc -isysroot $(SDK_MAC_MID_PATH) \
	    $(MAC_LDFLAGS) -lgcc_s.10.4 $^ -o $@

$(INT_DIR)/ppc/%.o: %.m
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_PPC) $(GCC_PPC) $(COMMON_CFLAGS) -arch ppc -isysroot $(SDK_MAC_MID_PATH) \
	    -fno-stack-protector -fno-common -fno-zero-initialized-in-bss -c $< -o $@

# --- Intel X86 Slice ---
$(INT_DIR)/x86.bin: $(X86_OBJS)
	@echo " > x86 (sdk:$(SDK_MAC_MID), min:$(MAC_MIN_X86))"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_X86) $(GCC_X86) -arch i386 -isysroot $(SDK_MAC_MID_PATH) \
	    $(MAC_LDFLAGS) $^ -o $@

$(INT_DIR)/x86/%.o: %.m
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_X86) $(GCC_X86) $(COMMON_CFLAGS) -arch i386 -isysroot $(SDK_MAC_MID_PATH) \
	    -c $< -o $@

# --- Intel X64 Slice ---
$(INT_DIR)/x64.bin: $(X64_OBJS)
	@echo " > x64 (sdk:$(SDK_MAC_MID), min:$(MAC_MIN_X64))"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_X64) $(GCC_X64) -arch x86_64 -isysroot $(SDK_MAC_MID_PATH) \
	    $(MAC_LDFLAGS) $^ -o $@

$(INT_DIR)/x64/%.o: %.m
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_X64) $(GCC_X64) $(COMMON_CFLAGS) -arch x86_64 -isysroot $(SDK_MAC_MID_PATH) \
	    -c $< -o $@

# --- Apple Silicon ARM Slice ---
$(INT_DIR)/arm64.bin: $(ARM_OBJS)
	@echo " > arm64 (sdk:$(SDK_MAC_NEW), min:$(MAC_MIN_ARM))"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_ARM) $(CLANG14) -target arm64-apple-macos11 -isysroot $(SDK_MAC_NEW_PATH) \
	    $(MAC_LDFLAGS) -fuse-ld=lld -B/usr/bin/ $^ -o $@

$(INT_DIR)/arm/%.o: %.m
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_ARM) $(CLANG14) -target arm64-apple-macos11 -arch arm64 -isysroot $(SDK_MAC_NEW_PATH) \
	    $(COMMON_CFLAGS) -c $< -o $@

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf build-release build-debug

.PHONY: release debug mac clean
