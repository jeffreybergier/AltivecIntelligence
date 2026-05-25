# Altivec Intelligence Common Makefile for Phone
# Targets: iOS 4.3+ (armv7, arm64)

# --- Tools and Paths ---
CLANG14 = /usr/bin/clang
DSYMUTIL = /usr/bin/dsymutil-14
BIN_DIR = /osxcross/target/bin
IOS_SDK_PATH = /osxcross/target/SDK/iPhoneOS8.4.sdk
# Capture self-dir immediately (:=) so it resolves while this file is still
# $(lastword MAKEFILE_LIST). With ?= alone the RHS is deferred and re-evaluates
# later, after downstream Makefiles include other .mk/.env files — then
# lastword points at those instead and ALTIVEC_ROOT silently mislocates.
_altivec_self_dir := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ALTIVEC_ROOT ?= $(_altivec_self_dir)

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

# --- Auto-detect libcurl ---
# LIBCURL_LINKAGE picks how libcurl is linked into the app.
#   static  (default): link the five .a archives directly into the binary.
#   dynamic          : link against AltivecCURL.framework; the framework
#                      is copied into <App>.app/Frameworks/ (iOS flat layout).
LIBCURL_LINKAGE ?= static
LIBCURL_DIR ?=
LIBCURL_SEARCH_PATHS = $(ALTIVEC_ROOT)/libs/libcurl/build-phone
ifeq ($(strip $(LIBCURL_DIR)),)
  LIBCURL_PATH = $(firstword $(wildcard $(addsuffix /lib/libcurl.a, $(LIBCURL_SEARCH_PATHS))))
  ifneq ($(LIBCURL_PATH),)
    LIBCURL_DIR = $(patsubst %/lib/libcurl.a,%,$(LIBCURL_PATH))
  endif
endif
ifneq ($(strip $(LIBCURL_DIR)),)
  ifeq ($(LIBCURL_LINKAGE),dynamic)
    LIBCURL_FRAMEWORK = $(LIBCURL_DIR)/lib/AltivecCURL.framework
    EXTRA_FLAGS += -F$(LIBCURL_DIR)/lib
  else
    EXTRA_FLAGS += -I$(LIBCURL_DIR)/include
  endif
endif

LIBCURL_REQUIRED ?= 0
ifeq ($(LIBCURL_LINKAGE),dynamic)
  LIBCURL_REQUIRED_FILES = $(LIBCURL_DIR)/lib/AltivecCURL.framework/AltivecCURL \
                           $(LIBCURL_DIR)/lib/AltivecCURL.framework/cacert.pem
else
  LIBCURL_REQUIRED_FILES = $(LIBCURL_DIR)/lib/libAICURLConnection.a \
                           $(LIBCURL_DIR)/lib/libcurl.a \
                           $(LIBCURL_DIR)/lib/libssl.a \
                           $(LIBCURL_DIR)/lib/libcrypto.a \
                           $(LIBCURL_DIR)/lib/libz.a \
                           $(LIBCURL_DIR)/lib/cacert.pem
endif

# --- Flags ---
IOS_FLAGS = $(OPT_FLAGS) $(EXTRA_FLAGS) -g -std=c99 -pedantic -Wall -Wextra -Wconversion -Wsign-conversion -Wfloat-conversion \
            -Wimplicit-function-declaration -Wobjc-method-access \
            -Wno-unused-command-line-argument -Wunguarded-availability -Wno-semicolon-before-method-body \
            -isysroot $(IOS_SDK_PATH) \
            -B$(BIN_DIR)

IOS_FRAMEWORKS = -framework UIKit -framework Foundation -framework CoreGraphics
ifneq ($(strip $(LIBCURL_DIR)),)
  ifeq ($(LIBCURL_LINKAGE),dynamic)
    IOS_FRAMEWORKS += -F$(LIBCURL_DIR)/lib -framework AltivecCURL \
                      -Wl,-rpath,@executable_path/Frameworks
  else
    IOS_FRAMEWORKS += $(LIBCURL_DIR)/lib/libAICURLConnection.a \
                      $(LIBCURL_DIR)/lib/libcurl.a \
                      $(LIBCURL_DIR)/lib/libssl.a \
                      $(LIBCURL_DIR)/lib/libcrypto.a \
                      $(LIBCURL_DIR)/lib/libz.a
  endif
endif

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

analyze: validate
	@echo "--- Running Clang Static Analyzer (arm64) ---"
	@$(CLANG14) --analyze -Xanalyzer -analyzer-output=text \
		-target arm64-apple-ios4.3 -arch arm64 -isysroot $(IOS_SDK_PATH) \
		$(IOS_FLAGS) $(ALL_SOURCES)

validate:
	@if [ ! -d "$(IOS_SDK_PATH)" ]; then echo " [!] ERROR: iOS SDK missing at $(IOS_SDK_PATH)"; exit 1; fi
	@if [ "$(LIBCURL_REQUIRED)" = "1" ]; then $(MAKE) --no-print-directory libcurl-bootstrap; fi
	@if [ "$(LIBCURL_REQUIRED)" = "1" ]; then $(MAKE) --no-print-directory libs-ready; fi
	@for dir in $(patsubst -I%,%,$(filter -I%,$(IOS_FLAGS))) $(patsubst -L%,%,$(filter -L%,$(IOS_FRAMEWORKS))); do \
		if [ ! -d "$$dir" ]; then \
			echo " [!] ERROR: Dependency directory missing: $$dir"; \
			echo "     This likely means a required library (like libcurl) hasn't been built."; \
			exit 1; \
		fi; \
	done

libcurl-bootstrap:
	@if [ "$(LIBCURL_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(LIBCURL_DIR)" ]; then \
		echo " [!] ERROR: libcurl is required but LIBCURL_DIR is not set or auto-detected."; \
		echo "     Set LIBCURL_DIR=/path/to/libs/libcurl/build-phone or build at $(ALTIVEC_ROOT)/libs/libcurl/build-phone."; \
		exit 1; \
	fi
	@probe="$(LIBCURL_DIR)/lib/libcurl.a"; target=phone-static; \
	if [ "$(LIBCURL_LINKAGE)" = "dynamic" ]; then \
		probe="$(LIBCURL_DIR)/lib/AltivecCURL.framework/AltivecCURL"; target=phone-all; \
	fi; \
	if [ ! -e "$$probe" ]; then \
		echo " [!] Missing libcurl artifact ($$probe), running bootstrap build ($$target)..."; \
		$(MAKE) -C $(ALTIVEC_ROOT)/libs/libcurl $$target; \
	fi

libs-ready:
	@if [ "$(LIBCURL_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(LIBCURL_DIR)" ]; then \
		echo " [!] ERROR: libcurl is required but LIBCURL_DIR is not set or auto-detected."; \
		echo "     Set LIBCURL_DIR=/path/to/libs/libcurl/build-phone."; \
		exit 1; \
	fi
	@missing=""; \
	for f in $(LIBCURL_REQUIRED_FILES); do \
		if [ ! -f "$$f" ]; then missing="$$missing $$f"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo " [!] ERROR: Missing required libcurl artifacts:$$missing"; \
		echo "     Build them with: make -C $(ALTIVEC_ROOT)/libs/libcurl phone-static"; \
		exit 1; \
	fi

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
	@if [ "$(LIBCURL_LINKAGE)" = "dynamic" ] && [ -d "$(LIBCURL_FRAMEWORK)" ]; then \
		echo "  > embedding AltivecCURL.framework" ; \
		mkdir -p $@/Frameworks ; \
		cp -RP $(LIBCURL_FRAMEWORK) $@/Frameworks/ ; \
	elif [ -f "$(LIBCURL_DIR)/lib/cacert.pem" ]; then \
		echo "  > copying cacert.pem" ; \
		cp "$(LIBCURL_DIR)/lib/cacert.pem" $@/ ; \
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

.PHONY: release debug clean analyze validate libcurl-bootstrap libs-ready
