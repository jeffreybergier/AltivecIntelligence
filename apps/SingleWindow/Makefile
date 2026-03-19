# Unified Triple-Architecture Makefile for SingleWindow
# Targets: Mac (PPC 10.4, i386 10.4, x86_64 10.5) and iPhone (8.2 SDK)

# Compilers
GCC_PPC=oppc32-gcc
GCC_I386=o32-gcc
GCC_X64=o64-gcc
CLANG14=/usr/bin/clang

# SDK Paths
MAC_SDK_PATH=/osxcross/target/SDK/MacOSX10.6.sdk
IOS_SDK_PATH=/osxcross/target/SDK/iPhoneOS8.2.sdk

# Build Settings
APP_NAME=SingleWindow
BUILD_DIR=build
INT_DIR=$(BUILD_DIR)/Intermediates
MAC_BUNDLE=$(BUILD_DIR)/$(APP_NAME).app
MAC_ZIP=$(BUILD_DIR)/$(APP_NAME).zip
IPHONE_IPA=$(BUILD_DIR)/$(APP_NAME)-i8.ipa

# Common Mac Flags
MAC_CFLAGS=-O2 -Wall -isysroot $(MAC_SDK_PATH)
MAC_LDFLAGS=-framework AppKit -lobjc

all: mac iphone

# --- MAC UNIVERSAL BUILD ---
mac: $(MAC_ZIP)

$(MAC_ZIP): $(MAC_BUNDLE)
	cd $(BUILD_DIR) && zip -r $(APP_NAME).zip $(APP_NAME).app

$(MAC_BUNDLE): $(INT_DIR)/$(APP_NAME)-universal
	mkdir -p $@/Contents/MacOS
	cp $< $@/Contents/MacOS/$(APP_NAME)
	cp Info_mac.plist $@/Contents/Info.plist
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

# --- IPHONE BUILD ---
iphone: $(IPHONE_IPA)

$(IPHONE_IPA): $(INT_DIR)/SingleWindow-i8-bin
	mkdir -p $(BUILD_DIR)
	rm -rf $(INT_DIR)/Payload
	mkdir -p $(INT_DIR)/Payload/SingleWindow-i8.app
	cp $(INT_DIR)/SingleWindow-i8-bin $(INT_DIR)/Payload/SingleWindow-i8.app/SingleWindow
	cp Info_iphone.plist $(INT_DIR)/Payload/SingleWindow-i8.app/Info.plist
	echo -n "APPL????" > $(INT_DIR)/Payload/SingleWindow-i8.app/PkgInfo
	cd $(INT_DIR) && zip -r ../$(notdir $@) Payload
	rm -rf $(INT_DIR)/Payload

$(INT_DIR)/SingleWindow-i8-bin: main_iphone.m
	mkdir -p $(INT_DIR)
	export PATH=/osxcross/target/bin:$(PATH); \
	$(CLANG14) -target arm64-apple-ios4.3 -isysroot $(IOS_SDK_PATH) \
	           -arch arm64 -arch armv7s -arch armv7 \
	           -B/osxcross/target/bin \
	           -O2 -Wall -Wimplicit-function-declaration -Wobjc-method-access \
	           -Wno-unused-command-line-argument -Wunguarded-availability \
	           -framework UIKit -framework Foundation -framework CoreGraphics \
	           main_iphone.m -o $@

clean:
	rm -rf $(BUILD_DIR) $(INT_DIR)

.PHONY: all mac iphone clean
