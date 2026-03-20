# Specialized Makefile for SingleScreen (iPhone)
# Targets: iOS 4.3+ (arm64, armv7s, armv7)

# Compilers
CLANG14=/usr/bin/clang
BIN_DIR=/osxcross/target/bin

# SDK Paths
IOS_SDK_PATH=/osxcross/target/SDK/iPhoneOS8.2.sdk

# Build Settings
APP_NAME=SingleScreen
BUILD_DIR=build
INT_DIR=$(BUILD_DIR)/Intermediates
IPHONE_IPA=$(BUILD_DIR)/$(APP_NAME)-i8.ipa

# Common Flags
# Note: We use -B to point to the cross-linker in the toolchain
IOS_FLAGS=-O2 -Wall \
          -Wimplicit-function-declaration -Wobjc-method-access \
          -Wno-unused-command-line-argument -Wunguarded-availability \
          -isysroot $(IOS_SDK_PATH) \
          -B$(BIN_DIR)

IOS_FRAMEWORKS=-framework UIKit -framework Foundation -framework CoreGraphics

all: $(IPHONE_IPA)

$(IPHONE_IPA): $(INT_DIR)/$(APP_NAME)-bin
	mkdir -p $(BUILD_DIR)
	rm -rf $(INT_DIR)/Payload
	mkdir -p $(INT_DIR)/Payload/$(APP_NAME).app
	cp $< $(INT_DIR)/Payload/$(APP_NAME).app/$(APP_NAME)
	cp Info_iphone.plist $(INT_DIR)/Payload/$(APP_NAME).app/Info.plist
	echo -n "APPL????" > $(INT_DIR)/Payload/$(APP_NAME).app/PkgInfo
	cd $(INT_DIR) && zip -r ../$(notdir $@) Payload
	rm -rf $(INT_DIR)/Payload

$(INT_DIR)/$(APP_NAME)-bin: main_iphone.m
	mkdir -p $(INT_DIR)
	export PATH=$(BIN_DIR):$(PATH); \
	$(CLANG14) -target arm64-apple-ios4.3 \
	           -arch arm64 -arch armv7s -arch armv7 \
	           $(IOS_FLAGS) $(IOS_FRAMEWORKS) \
	           main_iphone.m -o $@

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all clean
