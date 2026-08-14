# AltivecIntelligence Common Build Settings for AltivecCocoa
# Included by Makefile-mac and Makefile-phone.

# --- Font Awesome Free ---
FONTAWESOME_VERSION = 7.2.0
FONTAWESOME_CACHE_DIR = $(CWD)/tarballs/fontawesome-$(FONTAWESOME_VERSION)
FONTAWESOME_SOLID_FILE = $(FONTAWESOME_CACHE_DIR)/FA7-Solid-900.otf
FONTAWESOME_REGULAR_FILE = $(FONTAWESOME_CACHE_DIR)/FA7-Regular-400.otf
FONTAWESOME_BRANDS_FILE = $(FONTAWESOME_CACHE_DIR)/FA7-Brands-400.otf
FONTAWESOME_SOLID_SHA256 = \
  c1091147299a846195bbca8b26528de6c9af842f236e7db44a1c2e8c9df52372
FONTAWESOME_REGULAR_SHA256 = \
  c6265ca5839938625a3c8c37a00cdcb2633d1ad6ab2c096c97b590a27162b67a
FONTAWESOME_BRANDS_SHA256 = \
  5ca45a8966e2aca9199839e484e429ada36e525c7637fd910613ddfe51738375
FONTAWESOME_SOLID_SOURCE = Font%20Awesome%207%20Free-Solid-900.otf
FONTAWESOME_REGULAR_SOURCE = Font%20Awesome%207%20Free-Regular-400.otf
FONTAWESOME_BRANDS_SOURCE = Font%20Awesome%207%20Brands-Regular-400.otf
FONTAWESOME_REPOSITORY = FortAwesome/Font-Awesome
FONTAWESOME_VERSION_PATH = \
  $(FONTAWESOME_REPOSITORY)/$(FONTAWESOME_VERSION)
FONTAWESOME_JSDELIVR_PATH = \
  $(FONTAWESOME_REPOSITORY)@$(FONTAWESOME_VERSION)/otfs
FONTAWESOME_URL_ROOTS = \
  https://raw.githubusercontent.com/$(FONTAWESOME_VERSION_PATH)/otfs \
  https://fastly.jsdelivr.net/gh/$(FONTAWESOME_JSDELIVR_PATH) \
  https://gcore.jsdelivr.net/gh/$(FONTAWESOME_JSDELIVR_PATH)

COCOA_FONT_FILES = $(FONTAWESOME_SOLID_FILE) \
                   $(FONTAWESOME_REGULAR_FILE) \
                   $(FONTAWESOME_BRANDS_FILE)
COCOA_FONT_NOTICE = Resources/Fonts/LICENSE-Font-Awesome.txt

# Try each checksum-verified source independently before moving to its mirror.
FONT_DOWNLOAD_ATTEMPTS = 3
FONT_CURL_FLAGS = --fail --silent --show-error --location \
                  --proto '=https' --proto-redir '=https' \
                  --connect-timeout 30

define download_font_to_target
	@set -e; \
	expected_sha256="$(2)"; \
	tmp=''; \
	cleanup() { \
	  if test -n "$$tmp"; then rm -f "$$tmp"; fi; \
	}; \
	trap cleanup EXIT; \
	trap 'exit 1' HUP INT TERM; \
	verify_download() { \
	  actual_sha256="$$(sha256sum "$$1" | awk '{print $$1}')"; \
	  test "$$actual_sha256" = "$$expected_sha256"; \
	}; \
	if test -f "$@"; then \
	  if verify_download "$@"; then \
	    echo "  > verified cached Font Awesome file: $@"; \
	    exit 0; \
	  fi; \
	  echo " [!] Discarding invalid cached Font Awesome file: $@" >&2; \
	  rm -f "$@"; \
	fi; \
	for root in $(FONTAWESOME_URL_ROOTS); do \
	  url="$$root/$(1)"; \
	  attempt=1; \
	  while test "$$attempt" -le "$(FONT_DOWNLOAD_ATTEMPTS)"; do \
	    tmp="$$(mktemp "$@.tmp.XXXXXX")"; \
	    echo "  > downloading $$url" \
	         "(attempt $$attempt/$(FONT_DOWNLOAD_ATTEMPTS))"; \
	    if curl $(FONT_CURL_FLAGS) "$$url" -o "$$tmp"; then \
	      if verify_download "$$tmp"; then \
	        mv "$$tmp" "$@"; \
	        tmp=''; \
	        exit 0; \
	      fi; \
	      actual_sha256="$$(sha256sum "$$tmp" | awk '{print $$1}')"; \
	      echo " [!] Checksum mismatch from $$url: $$actual_sha256" >&2; \
	    fi; \
	    rm -f "$$tmp"; \
	    tmp=''; \
	    if test "$$attempt" -lt "$(FONT_DOWNLOAD_ATTEMPTS)"; then \
	      sleep "$$((attempt * 2))"; \
	    fi; \
	    attempt="$$((attempt + 1))"; \
	  done; \
	done; \
	echo " [!] ERROR: failed to download and verify $@" >&2; \
	exit 1
endef

$(FONTAWESOME_CACHE_DIR):
	mkdir -p $@

$(FONTAWESOME_SOLID_FILE): FONT_SOURCE = $(FONTAWESOME_SOLID_SOURCE)
$(FONTAWESOME_SOLID_FILE): FONT_SHA256 = $(FONTAWESOME_SOLID_SHA256)
$(FONTAWESOME_REGULAR_FILE): FONT_SOURCE = $(FONTAWESOME_REGULAR_SOURCE)
$(FONTAWESOME_REGULAR_FILE): FONT_SHA256 = $(FONTAWESOME_REGULAR_SHA256)
$(FONTAWESOME_BRANDS_FILE): FONT_SOURCE = $(FONTAWESOME_BRANDS_SOURCE)
$(FONTAWESOME_BRANDS_FILE): FONT_SHA256 = $(FONTAWESOME_BRANDS_SHA256)

$(COCOA_FONT_FILES): force-font-download-check | $(FONTAWESOME_CACHE_DIR)
	$(call download_font_to_target,$(FONT_SOURCE),$(FONT_SHA256))

fontawesome-fetch: $(COCOA_FONT_FILES)

force-font-download-check:

.PHONY: fontawesome-fetch force-font-download-check

# --- Toolchain Paths ---
include $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../altivec_toolchains.mk)
BIN_DIR=$(MODERN_BIN)

# --- Standard Flags ---
OPT_FLAGS=-O3
COMMON_WARN_FLAGS=-Wall -Wextra -Wno-deprecated-declarations
CLANG_WARN_FLAGS=$(COMMON_WARN_FLAGS) -Wno-semicolon-before-method-body
LEGACY_GCC_FLAGS=-fno-stack-protector -fno-common -fno-zero-initialized-in-bss -fPIC

# --- Deployment Targets ---
MAC_MIN_PPC=10.4
MAC_MIN_X86=10.4
MAC_MIN_X64=10.9
MAC_MIN_ARM64=11.0
IOS_MIN_VER=5.0
IOS_ARM64_MIN_VER=7.0

plist_version = $(shell python3 -c 'import plistlib; print(plistlib.load(open("$(1)", "rb"))["CFBundleVersion"])')
