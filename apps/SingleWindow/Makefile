# Unified Triple-Architecture Makefile for SingleWindow
# Targets: Mac (PPC 10.4, i386 10.4, x86_64 10.5)

# Compilers
GCC_PPC=oppc32-gcc
GCC_I386=o32-gcc
GCC_X64=o64-gcc

# Tools
DSYMUTIL=/usr/bin/dsymutil-14

# SDK Paths
MAC_SDK_PATH=/osxcross/target/SDK/MacOSX10.6.sdk

# Silence osxcross dsymutil warnings
export OSXCROSS_NO_DSYMUTIL=1

# App Identity
APP_NAME=SingleWindow
RES_DIR=Resources

# Default build settings (Overridden by debug/release targets)
BUILD_DIR=build-release
OPT_FLAGS=-O2

# Common Mac Flags
MAC_CFLAGS=$(OPT_FLAGS) -g -Wall -isysroot $(MAC_SDK_PATH)
MAC_LDFLAGS=-framework AppKit -lobjc

# --- TOP LEVEL TARGETS ---

# Default: Release Build
release:
	$(MAKE) mac BUILD_DIR=build-release OPT_FLAGS=-O3

# Debug Build
debug:
	$(MAKE) mac BUILD_DIR=build-debug OPT_FLAGS=-O0

# --- MAC UNIVERSAL BUILD ---

# Internal target variables (Deferred evaluation)
INT_DIR=$(BUILD_DIR)/Intermediates
MAC_BUNDLE=$(BUILD_DIR)/$(APP_NAME).app
MAC_ZIP=$(BUILD_DIR)/$(APP_NAME).zip

mac: $(MAC_ZIP)

$(MAC_ZIP): $(MAC_BUNDLE)
	cd $(BUILD_DIR) && zip -rq $(APP_NAME).zip $(APP_NAME).app

$(MAC_BUNDLE): $(INT_DIR)/$(APP_NAME)-universal
	mkdir -p $@/Contents/MacOS $@/Contents/Resources
	# Copy the universal binary
	cp $< $@/Contents/MacOS/$(APP_NAME)
	# Copy the Info.plist
	cp $(RES_DIR)/Info.plist $@/Contents/Info.plist
	# Copy all other resources
	find $(RES_DIR) -type f ! -name "Info.plist" -exec cp {} $@/Contents/Resources/ \;
	
	# SYMBOL EXTRACTION (x86_64 Only)
	# Creates portable .dSYM in the build folder
	$(DSYMUTIL) $(INT_DIR)/x86_64.bin -o $(BUILD_DIR)/$(APP_NAME).dSYM
	
	echo -n "APPL????" > $@/Contents/PkgInfo

$(INT_DIR)/$(APP_NAME)-universal: $(INT_DIR)/ppc.bin $(INT_DIR)/i386.bin $(INT_DIR)/x86_64.bin
	lipo -create $^ -output $@

# PowerPC Slice
$(INT_DIR)/ppc.bin: $(INT_DIR)/ppc.o
	MACOSX_DEPLOYMENT_TARGET=10.4 $(GCC_PPC) -arch ppc -isysroot $(MAC_SDK_PATH) $< $(MAC_LDFLAGS) -lgcc_s.10.4 -o $@

$(INT_DIR)/ppc.o: main_mac.m
	mkdir -p $(INT_DIR)
	MACOSX_DEPLOYMENT_TARGET=10.4 $(GCC_PPC) $(MAC_CFLAGS) -arch ppc \
	    -fno-stack-protector -fno-common -fno-zero-initialized-in-bss \
	    -c $< -o $@

# i386 Slice
$(INT_DIR)/i386.bin: $(INT_DIR)/i386.o
	MACOSX_DEPLOYMENT_TARGET=10.4 $(GCC_I386) -arch i386 -isysroot $(MAC_SDK_PATH) $< $(MAC_LDFLAGS) -o $@

$(INT_DIR)/i386.o: main_mac.m
	mkdir -p $(INT_DIR)
	MACOSX_DEPLOYMENT_TARGET=10.4 $(GCC_I386) $(MAC_CFLAGS) -arch i386 -c $< -o $@

# x86_64 Slice
$(INT_DIR)/x86_64.bin: $(INT_DIR)/x86_64.o
	MACOSX_DEPLOYMENT_TARGET=10.5 $(GCC_X64) -arch x86_64 -isysroot $(MAC_SDK_PATH) $< $(MAC_LDFLAGS) -o $@

$(INT_DIR)/x86_64.o: main_mac.m
	mkdir -p $(INT_DIR)
	MACOSX_DEPLOYMENT_TARGET=10.5 $(GCC_X64) $(MAC_CFLAGS) -arch x86_64 -c $< -o $@

clean:
	rm -rf build-release build-debug

.PHONY: release debug mac clean
