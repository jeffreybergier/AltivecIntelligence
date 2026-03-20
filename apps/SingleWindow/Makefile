# Unified Triple-Architecture Makefile for SingleWindow
# Targets: Mac (PPC 10.4, i386 10.4, x86_64 10.5)
# Uses the 10.6 Super SDK

# Compilers
GCC_PPC=oppc32-gcc
GCC_I386=o32-gcc
GCC_X64=o64-gcc

# SDK Paths
MAC_SDK_PATH=/osxcross/target/SDK/MacOSX10.6.sdk

# Build Settings
APP_NAME=SingleWindow
BUILD_DIR=build
INT_DIR=$(BUILD_DIR)/Intermediates
MAC_BUNDLE=$(BUILD_DIR)/$(APP_NAME).app
MAC_ZIP=$(BUILD_DIR)/$(APP_NAME).zip
RES_DIR=Resources

# Common Mac Flags
MAC_CFLAGS=-O2 -Wall -isysroot $(MAC_SDK_PATH)
MAC_LDFLAGS=-framework AppKit -lobjc

release: mac

# --- MAC UNIVERSAL BUILD ---
mac: $(MAC_ZIP)

$(MAC_ZIP): $(MAC_BUNDLE)
	cd $(BUILD_DIR) && zip -rq $(APP_NAME).zip $(APP_NAME).app

$(MAC_BUNDLE): $(INT_DIR)/$(APP_NAME)-universal
	mkdir -p $@/Contents/MacOS $@/Contents/Resources
	# Copy the binary
	cp $< $@/Contents/MacOS/$(APP_NAME)
	# Copy the Info.plist specifically to Contents/
	cp $(RES_DIR)/Info.plist $@/Contents/Info.plist
	# Blindly copy ALL other files from Resources/ into Contents/Resources/
	# We use find to skip the Info.plist itself
	find $(RES_DIR) -type f ! -name "Info.plist" -exec cp {} $@/Contents/Resources/ \;
	echo -n "APPL????" > $@/Contents/PkgInfo

$(INT_DIR)/$(APP_NAME)-universal: $(INT_DIR)/ppc.bin $(INT_DIR)/i386.bin $(INT_DIR)/x86_64.bin
	lipo -create $^ -output $@

# PowerPC Slice (Targeting Tiger 10.4+)
$(INT_DIR)/ppc.bin: main_mac.m
	mkdir -p $(INT_DIR)
	MACOSX_DEPLOYMENT_TARGET=10.4 $(GCC_PPC) $(MAC_CFLAGS) -arch ppc \
	    -fno-stack-protector -fno-common -fno-zero-initialized-in-bss \
	    main_mac.m $(MAC_LDFLAGS) -lgcc_s.10.4 -o $@

# i386 Slice (Targeting Tiger 10.4+)
$(INT_DIR)/i386.bin: main_mac.m
	mkdir -p $(INT_DIR)
	MACOSX_DEPLOYMENT_TARGET=10.4 $(GCC_I386) $(MAC_CFLAGS) -arch i386 main_mac.m $(MAC_LDFLAGS) -o $@

# x86_64 Slice (Targeting Leopard 10.5+)
$(INT_DIR)/x86_64.bin: main_mac.m
	mkdir -p $(INT_DIR)
	MACOSX_DEPLOYMENT_TARGET=10.5 $(GCC_X64) $(MAC_CFLAGS) -arch x86_64 main_mac.m $(MAC_LDFLAGS) -o $@

clean:
	rm -rf $(BUILD_DIR)

.PHONY: release mac clean
