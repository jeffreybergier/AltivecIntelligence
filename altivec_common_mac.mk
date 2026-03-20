# Altivec Intelligence Common Makefile
# This file contains the standard logic for Triple-Architecture Mac Apps

# --- Versions ---
SDK_VER = 10.6
PPC_MIN = 10.4
I386_MIN = 10.4
X64_MIN = 10.5

# --- Compilers ---
GCC_PPC=oppc32-gcc
GCC_I386=o32-gcc
GCC_X64=o64-gcc
DSYMUTIL=/usr/bin/dsymutil-14

# --- SDK Configuration ---
MAC_SDK_PATH=/osxcross/target/SDK/MacOSX$(SDK_VER).sdk
export OSXCROSS_NO_DSYMUTIL=1

# --- Default Build Settings ---
BUILD_DIR ?= build-release
INT_DIR = $(BUILD_DIR)/Intermediates
OPT_FLAGS ?= -O3

# --- Flags ---
MAC_CFLAGS = $(OPT_FLAGS) -g -Wall -isysroot $(MAC_SDK_PATH)
MAC_LDFLAGS = -framework AppKit -lobjc

# --- Target Paths ---
BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
ZIP_FILE = $(BUILD_DIR)/$(APP_NAME).zip
RES_DIR ?= Resources
INFO_PLIST ?= Info.plist

# --- Top Level Targets ---

# Default action (Release)
release:
	@echo "--- Building Mac Release (-O3) ---"
	@$(MAKE) --no-print-directory mac BUILD_DIR=build-release OPT_FLAGS=-O3

# Debug action
debug:
	@echo "--- Building Mac Debug (-O0) ---"
	@$(MAKE) --no-print-directory mac BUILD_DIR=build-debug OPT_FLAGS=-O0

# --- The "Universal" Build Engine ---
mac: $(ZIP_FILE)

$(ZIP_FILE): $(BUNDLE)
	@echo "[4/4] Zipping package..."
	@cd $(BUILD_DIR) && zip -rq $(APP_NAME).zip $(APP_NAME).app

$(BUNDLE): $(INT_DIR)/$(APP_NAME)-universal
	@echo "[3/4] Building app package..."
	@mkdir -p $@/Contents/MacOS $@/Contents/Resources
	@cp $< $@/Contents/MacOS/$(APP_NAME)
	@cp $(INFO_PLIST) $@/Contents/Info.plist
	@if [ -d "$(RES_DIR)" ] && [ "$$(ls -A $(RES_DIR) 2>/dev/null)" ]; then \
		cp -R $(RES_DIR)/* $@/Contents/Resources/ ; \
	fi
	@$(DSYMUTIL) $(INT_DIR)/x86_64.bin -o $(BUILD_DIR)/$(APP_NAME).dSYM
	@echo -n "APPL????" > $@/Contents/PkgInfo

$(INT_DIR)/$(APP_NAME)-universal: $(INT_DIR)/ppc.bin $(INT_DIR)/i386.bin $(INT_DIR)/x86_64.bin
	@lipo -create $^ -output $@

# PowerPC Slice
$(INT_DIR)/ppc.bin: $(INT_DIR)/ppc.o
	@MACOSX_DEPLOYMENT_TARGET=$(PPC_MIN) $(GCC_PPC) -arch ppc -isysroot $(MAC_SDK_PATH) $< $(MAC_LDFLAGS) -lgcc_s.10.4 -o $@

$(INT_DIR)/ppc.o: $(SOURCES)
	@echo "[1/4] Compiling slices..."
	@echo "      > ppc (sdk:$(SDK_VER), min:$(PPC_MIN))"
	@mkdir -p $(INT_DIR)
	@MACOSX_DEPLOYMENT_TARGET=$(PPC_MIN) $(GCC_PPC) $(MAC_CFLAGS) -arch ppc \
	    -fno-stack-protector -fno-common -fno-zero-initialized-in-bss \
	    -c $< -o $@

# i386 Slice
$(INT_DIR)/i386.bin: $(INT_DIR)/i386.o
	@MACOSX_DEPLOYMENT_TARGET=$(I386_MIN) $(GCC_I386) -arch i386 -isysroot $(MAC_SDK_PATH) $< $(MAC_LDFLAGS) -o $@

$(INT_DIR)/i386.o: $(SOURCES)
	@echo "      > i386 (sdk:$(SDK_VER), min:$(I386_MIN))"
	@mkdir -p $(INT_DIR)
	@MACOSX_DEPLOYMENT_TARGET=$(I386_MIN) $(GCC_I386) $(MAC_CFLAGS) -arch i386 -c $< -o $@

# x86_64 Slice
$(INT_DIR)/x86_64.bin: $(INT_DIR)/x86_64.o
	@MACOSX_DEPLOYMENT_TARGET=$(X64_MIN) $(GCC_X64) -arch x86_64 -isysroot $(MAC_SDK_PATH) $< $(MAC_LDFLAGS) -o $@

$(INT_DIR)/x86_64.o: $(SOURCES)
	@echo "      > x86_64 (sdk:$(SDK_VER), min:$(X64_MIN))"
	@mkdir -p $(INT_DIR)
	@MACOSX_DEPLOYMENT_TARGET=$(X64_MIN) $(GCC_X64) $(MAC_CFLAGS) -arch x86_64 -c $< -o $@

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf build-release build-debug

.PHONY: release debug mac clean
