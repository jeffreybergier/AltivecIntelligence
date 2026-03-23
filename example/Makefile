# Compilers
CLANG3=o64-clang
GCC4=oppc32-gcc
CLANG14=/usr/bin/clang

# SDK Paths
MAC_SDK_PATH=/osxcross/target/SDK/MacOSX10.6.sdk
TIGER_SDK_PATH=/osxcross/target/SDK/MacOSX10.4u.sdk
IOS_SDK_PATH=/osxcross/target/SDK/iPhoneOS8.2.sdk

BIN_DIR=/osxcross/target/bin

# Build Settings
OPT_FLAGS=-O2
COMMON_WARN_FLAGS=-Wall -Wimplicit-function-declaration
CLANG_WARN_FLAGS=-Wobjc-method-access -Wno-unused-command-line-argument -Wunguarded-availability

# Combined Flags
MAC_IPHONE_FLAGS=$(OPT_FLAGS) $(COMMON_WARN_FLAGS) $(CLANG_WARN_FLAGS)
TIGER_FLAGS=$(OPT_FLAGS) $(COMMON_WARN_FLAGS)

# App Identity
APP_NAME=Example
BUILD_DIR=build
MAC_FRAMEWORKS=-framework AppKit
IOS_FRAMEWORKS=-framework UIKit -framework Foundation -framework CoreGraphics

all: mac tiger iphone

# --- MAC (10.6 SDK, Leopard/Snow Leopard) ---
MAC_NAME=$(APP_NAME)-X6
MAC_DIR=$(BUILD_DIR)/$(MAC_NAME).app
MAC_BIN=$(BUILD_DIR)/$(APP_NAME)-X6-bin

mac: $(BUILD_DIR)/$(MAC_NAME).zip

$(BUILD_DIR)/$(MAC_NAME).zip: $(MAC_DIR)
	cd $(BUILD_DIR) && zip -r $(MAC_NAME).zip $(MAC_NAME).app

$(MAC_DIR): $(MAC_BIN) Info_mac.plist
	mkdir -p $(MAC_DIR)/Contents/MacOS $(MAC_DIR)/Contents/Resources
	cp $(MAC_BIN) $(MAC_DIR)/Contents/MacOS/$(APP_NAME)
	cp Info_mac.plist $(MAC_DIR)/Contents/Info.plist
	echo -n "APPL????" > $(MAC_DIR)/Contents/PkgInfo

$(MAC_BIN): main_mac.m
	mkdir -p $(BUILD_DIR)
	SDK_VERSION=10.6 OSXCROSS_SDKROOT=$(MAC_SDK_PATH) $(CLANG3) -arch x86_64 -arch i386 -arch ppc -Xarch_ppc -fobjc-abi-version=1 -mmacosx-version-min=10.5 $(MAC_IPHONE_FLAGS) $(MAC_FRAMEWORKS) main_mac.m -o $(MAC_BIN)

# --- TIGER (10.4u SDK, Tiger PPC) ---
TIGER_NAME=$(APP_NAME)-X4
TIGER_DIR=$(BUILD_DIR)/$(TIGER_NAME).app
TIGER_BIN=$(BUILD_DIR)/$(APP_NAME)-X4-bin

tiger: $(BUILD_DIR)/$(TIGER_NAME).zip

$(BUILD_DIR)/$(TIGER_NAME).zip: $(TIGER_DIR)
	cd $(BUILD_DIR) && zip -r $(TIGER_NAME).zip $(TIGER_NAME).app

$(TIGER_DIR): $(TIGER_BIN) Info_mac.plist
	mkdir -p $(TIGER_DIR)/Contents/MacOS $(TIGER_DIR)/Contents/Resources
	cp $(TIGER_BIN) $(TIGER_DIR)/Contents/MacOS/$(APP_NAME)
	cp Info_mac.plist $(TIGER_DIR)/Contents/Info.plist
	echo -n "APPL????" > $(TIGER_DIR)/Contents/PkgInfo

$(TIGER_BIN): main_mac.m
	mkdir -p $(BUILD_DIR)
	MACOSX_DEPLOYMENT_TARGET=10.4 SDK_VERSION=10.4u OSXCROSS_SDKROOT=$(TIGER_SDK_PATH) OSX_VERSION_MIN=10.4 $(GCC4) -arch ppc -mmacosx-version-min=10.4 -fno-stack-protector -fno-common -fno-zero-initialized-in-bss $(TIGER_FLAGS) $(MAC_FRAMEWORKS) -lobjc -lgcc_s.10.4 main_mac.m -o $(TIGER_BIN)

# --- IPHONE (8.2 SDK, iOS 4.3+) ---
IPHONE_NAME=$(APP_NAME)-i8
IPHONE_DIR=$(BUILD_DIR)/$(IPHONE_NAME).app
IPHONE_BIN=$(BUILD_DIR)/$(IPHONE_NAME)-bin
IPHONE_IPA=$(BUILD_DIR)/$(IPHONE_NAME).ipa

iphone: $(IPHONE_IPA)

$(IPHONE_IPA): $(IPHONE_DIR)
	rm -rf $(BUILD_DIR)/Payload
	mkdir -p $(BUILD_DIR)/Payload
	cp -R $(IPHONE_DIR) $(BUILD_DIR)/Payload/
	cd $(BUILD_DIR) && zip -r $(IPHONE_NAME).ipa Payload
	rm -rf $(BUILD_DIR)/Payload

$(IPHONE_DIR): $(IPHONE_BIN) Info_iphone.plist
	mkdir -p $(IPHONE_DIR)
	cp $(IPHONE_BIN) $(IPHONE_DIR)/$(APP_NAME)
	cp Info_iphone.plist $(IPHONE_DIR)/Info.plist
	echo -n "APPL????" > $(IPHONE_DIR)/PkgInfo

$(IPHONE_BIN): main_iphone.m
	mkdir -p $(BUILD_DIR)
	export PATH=$(BIN_DIR):$(PATH); \
	$(CLANG14) -target arm64-apple-ios4.3 -isysroot $(IOS_SDK_PATH) \
	           -arch arm64 -arch armv7s -arch armv7 \
	           -B$(BIN_DIR) $(MAC_IPHONE_FLAGS) $(IOS_FRAMEWORKS) main_iphone.m -o $(IPHONE_BIN)

clean:
	rm -rf $(BUILD_DIR)
