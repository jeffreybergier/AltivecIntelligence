# AltivecIntelligence Common Build Settings for libcurl
# Included by Makefile-phone and Makefile-mac

# --- Toolchain Paths ---
include $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../altivec_toolchains.mk)
BIN_DIR=$(MODERN_BIN)

# --- Standard Flags ---
OPT_FLAGS=-O3
COMMON_WARN_FLAGS=-Wall -Wimplicit-function-declaration
# zlib 1.2.13 defines fdopen as a function-like NULL macro whenever Apple's
# TARGET_OS_MAC macro exists. Modern Clang then expands that macro inside the iOS
# SDK's stdio declaration. A self-referential object macro marks fdopen as
# available without rewriting either the SDK or the vendored source.
ZLIB_MODERN_CFLAGS=$(OPT_FLAGS) -Dfdopen=fdopen \
                    -Wno-deprecated-non-prototype -Wno-macro-redefined

# --- Deployment Targets ---
MAC_MIN_PPC=10.4
MAC_MIN_X86=10.4
MAC_MIN_X64=10.9
MAC_MIN_ARM64=11.0
IOS_MIN_VER=4.3

# PPC specific flags from altivec_common_mac.mk
# -fPIC: required so static .o files can be re-linked into AltivecCore.dylib.
#        Modern (x64/arm64) arches default to PIC; legacy GCC needs it explicit.
LEGACY_GCC_FLAGS=-fno-stack-protector -fno-common -fno-zero-initialized-in-bss -fPIC
PPC_COMPAT_FLAGS=$(LEGACY_GCC_FLAGS)

# Jobs for parallel make
JOBS=$(shell getconf _NPROCESSORS_ONLN)

# Network downloads are part of dependency bootstrapping. Use retries and a
# temporary output file so transient CDN errors do not leave corrupt archives.
CURL_RETRY_FLAGS=--fail --location --retry 5 --retry-delay 2 \
                 --retry-all-errors --connect-timeout 30

define download_to_target
	@set -e; \
	validate_download() { \
	  case "$$2" in \
	    *.tar.gz) tar -tzf "$$1" >/dev/null 2>&1 ;; \
	    *.pem) grep -q -- '-----BEGIN CERTIFICATE-----' "$$1" ;; \
	    *) test -s "$$1" ;; \
	  esac; \
	}; \
	if test -f "$@"; then \
	  if validate_download "$@" "$@"; then \
	    exit 0; \
	  fi; \
	  echo " [!] Invalid cached download: $@"; \
	  rm -f "$@"; \
	fi; \
	tmp="$@.tmp"; \
	rm -f "$$tmp"; \
	for url in $(1); do \
	  echo "  > downloading $$url"; \
	  if curl $(CURL_RETRY_FLAGS) "$$url" -o "$$tmp"; then \
	    if validate_download "$$tmp" "$@"; then \
	      mv "$$tmp" "$@"; \
	      exit 0; \
	    fi; \
	    echo "  > rejected invalid response from $$url"; \
	  fi; \
	  rm -f "$$tmp"; \
	done; \
	echo " [!] ERROR: failed to download $@"; \
	exit 1
endef

# Re-run download recipes so cached files are validated before use. Valid
# files return immediately; invalid files are replaced from the configured URLs.
force-download-check:

.PHONY: force-download-check
