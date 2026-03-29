# Altivec Intelligence Common Makefile for Phone
# Targets: iOS 4.3+ (armv7, arm64)

# --- Tools and Paths ---
CLANG14 = /usr/bin/clang
DSYMUTIL = /usr/bin/dsymutil-14
BIN_DIR = /osxcross/target/bin
IOS_SDK_PATH = /osxcross/target/SDK/iPhoneOS8.4.sdk

# --- Default Build Settings ---
BUILD_DIR ?= build-release
INT_DIR = $(BUILD_DIR)/Intermediates
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
PHONE_IPA = $(BUILD_DIR)/$(APP_NAME).ipa
RES_DIR ?= Resources
INFO_PLIST ?= Info.plist
OPT_FLAGS ?= -O3

# --- Object Mapping ---
# Support both .m and .c files in SOURCES and EXTRA_SOURCES
ALL_SOURCES = $(SOURCES) $(EXTRA_SOURCES)
OBJS = $(addprefix $(INT_DIR)/, $(filter %.o, $(SOURCES:.m=.o) $(SOURCES:.c=.o) $(EXTRA_SOURCES:.m=.o) $(EXTRA_SOURCES:.c=.o)))

# --- Flags ---
IOS_FLAGS = $(OPT_FLAGS) $(EXTRA_FLAGS) -g -Wall \
            -Wimplicit-function-declaration -Wobjc-method-access \
            -Wno-unused-command-line-argument -Wunguarded-availability \
            -isysroot $(IOS_SDK_PATH) \
            -B$(BIN_DIR)

IOS_FRAMEWORKS = -framework UIKit -framework Foundation -framework CoreGraphics

# --- Top Level Targets ---
.DEFAULT_GOAL := release

release: validate
	@echo "--- Building Phone Release ($(OPT_FLAGS)) ---"
	@$(MAKE) --no-print-directory build-release/$(APP_NAME).ipa BUILD_DIR=build-release OPT_FLAGS=-O3

debug: validate
	@echo "--- Building Phone Debug (-O0) ---"
	@$(MAKE) --no-print-directory build-debug/$(APP_NAME).ipa BUILD_DIR=build-debug OPT_FLAGS=-O0

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf build-release build-debug

validate:
	@if [ ! -d "$(IOS_SDK_PATH)" ]; then echo " [!] ERROR: iOS SDK missing at $(IOS_SDK_PATH)"; exit 1; fi
	@for dir in $(patsubst -I%,%,$(filter -I%,$(IOS_FLAGS))) $(patsubst -L%,%,$(filter -L%,$(IOS_FRAMEWORKS))); do \
		if [ ! -d "$$dir" ]; then \
			echo " [!] ERROR: Dependency directory missing: $$dir"; \
			echo "     This likely means a required library (like libcurl) hasn't been built."; \
			exit 1; \
		fi; \
	done

# --- Internal File Targets ---

$(PHONE_IPA): $(APP_BUNDLE)
	@echo " [4/4] Packaging IPA..."
	@rm -rf $(INT_DIR)/Payload
	@mkdir -p $(INT_DIR)/Payload
	@cp -R $(APP_BUNDLE) $(INT_DIR)/Payload/
	@cd $(INT_DIR) && zip -rq ../../$@ Payload
	@rm -rf $(INT_DIR)/Payload

$(APP_BUNDLE): $(INT_DIR)/$(APP_NAME)-bin
	@echo " [3/4] Building app package..."
	@mkdir -p $@
	@echo "  > copying binary"
	@cp $< $@/$(APP_NAME)
	@echo "  > copying Info.plist"
	@cp $(INFO_PLIST) $@/Info.plist
	@if [ -d "$(RES_DIR)" ] && [ "$$(ls -A $(RES_DIR) 2>/dev/null)" ]; then \
		echo "  > copying resources" ; \
		cp -R $(RES_DIR)/* $@/ ; \
	fi
	@if [ -f "$(CURL_DIR)/lib/cacert.pem" ]; then \
		echo "  > copying cacert.pem" ; \
		cp "$(CURL_DIR)/lib/cacert.pem" $@/ ; \
	fi
	@echo "  > extracting symbols"
	@$(DSYMUTIL) $< -o $(BUILD_DIR)/$(APP_NAME).dSYM
	@echo -n "APPL????" > $@/PkgInfo

# Compile and Link in two steps to preserve .o files for dsymutil
$(INT_DIR)/$(APP_NAME)-bin: $(OBJS)
	@echo " [2/4] Linking Phone universal binary (armv7, arm64)..."
	@export PATH=$(BIN_DIR):$(PATH); \
	$(CLANG14) -target arm64-apple-ios4.3 -arch armv7 -arch arm64 \
	           $(IOS_FLAGS) $(IOS_FRAMEWORKS) $(LIBS_IPHONE) $^ -o $@

$(INT_DIR)/%.o: %.m
	@mkdir -p $(INT_DIR)
	@if [ "$(notdir $<)" = "$(firstword $(notdir $(ALL_SOURCES)))" ]; then \
		echo " [1/4] Compiling Files..."; \
	fi
	@echo "  > $(notdir $<)"
	@$(CLANG14) -target arm64-apple-ios4.3 -arch armv7 -arch arm64 \
	           $(IOS_FLAGS) -c $< -o $@

$(INT_DIR)/%.o: %.c
	@mkdir -p $(INT_DIR)
	@if [ "$(notdir $<)" = "$(firstword $(notdir $(ALL_SOURCES)))" ]; then \
		echo " [1/4] Compiling Files..."; \
	fi
	@echo "  > $(notdir $<)"
	@$(CLANG14) -target arm64-apple-ios4.3 -arch armv7 -arch arm64 \
	           $(IOS_FLAGS) -c $< -o $@

.PHONY: release debug clean validate
