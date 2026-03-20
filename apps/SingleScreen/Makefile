# Specialized Makefile for SingleScreen (iPhone)
# Targets: iOS 4.3+ (armv7, arm64)

# 1. Project Identity
APP_NAME = SingleScreen
SOURCES = main_iphone.m
RES_DIR = Resources
INFO_PLIST = Info_iphone.plist

# 2. Compilers and Tools
CLANG14 = /usr/bin/clang
DSYMUTIL = /usr/bin/dsymutil-14
BIN_DIR = /osxcross/target/bin
IOS_SDK_PATH = /osxcross/target/SDK/iPhoneOS8.4.sdk

# 3. Default Build Settings
BUILD_DIR ?= build-release
INT_DIR = $(BUILD_DIR)/Intermediates
IPHONE_IPA = $(BUILD_DIR)/$(APP_NAME).ipa
OPT_FLAGS ?= -O2

# 4. Common Flags
IOS_FLAGS = $(OPT_FLAGS) -g -Wall \
            -Wimplicit-function-declaration -Wobjc-method-access \
            -Wno-unused-command-line-argument -Wunguarded-availability \
            -isysroot $(IOS_SDK_PATH) \
            -B$(BIN_DIR)

IOS_FRAMEWORKS = -framework UIKit -framework Foundation -framework CoreGraphics

# --- Top Level Targets ---

release:
	@echo "--- Building iPhone Release ($(OPT_FLAGS)) ---"
	@$(MAKE) --no-print-directory iphone BUILD_DIR=build-release OPT_FLAGS=-O2

debug:
	@echo "--- Building iPhone Debug (-O0) ---"
	@$(MAKE) --no-print-directory iphone BUILD_DIR=build-debug OPT_FLAGS=-O0

iphone: $(IPHONE_IPA)

$(IPHONE_IPA): $(INT_DIR)/$(APP_NAME)-bin
	@mkdir -p $(BUILD_DIR)
	@rm -rf $(INT_DIR)/Payload
	@mkdir -p $(INT_DIR)/Payload/$(APP_NAME).app
	# Copy binary
	@cp $< $(INT_DIR)/Payload/$(APP_NAME).app/$(APP_NAME)
	# Copy Info.plist
	@cp $(INFO_PLIST) $(INT_DIR)/Payload/$(APP_NAME).app/Info.plist
	# Blind Copy all resources
	@if [ -d "$(RES_DIR)" ] && [ "$$(ls -A $(RES_DIR) 2>/dev/null)" ]; then \
		cp -R $(RES_DIR)/* $(INT_DIR)/Payload/$(APP_NAME).app/ ; \
	fi
	# Extract symbols
	@echo "Extracting symbols..."
	@$(DSYMUTIL) $< -o $(BUILD_DIR)/$(APP_NAME).dSYM
	# Finalize
	@echo -n "APPL????" > $(INT_DIR)/Payload/$(APP_NAME).app/PkgInfo
	@echo "Packaging IPA..."
	@cd $(INT_DIR) && zip -rq ../$(notdir $@) Payload
	@rm -rf $(INT_DIR)/Payload

# SINGLE CLANG COMMAND (armv7 and arm64 only)
$(INT_DIR)/$(APP_NAME)-bin: $(SOURCES)
	@mkdir -p $(INT_DIR)
	@echo "Compiling iPhone universal binary (armv7, arm64) in ONE shot..."
	@export PATH=$(BIN_DIR):$(PATH); \
	$(CLANG14) -target arm64-apple-ios4.3 \
	           -arch armv7 -arch arm64 \
	           $(IOS_FLAGS) $(IOS_FRAMEWORKS) \
	           $< -o $@

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf build-release build-debug

.PHONY: release debug iphone clean
