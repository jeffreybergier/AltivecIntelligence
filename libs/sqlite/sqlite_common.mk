# AltivecIntelligence Common Build Settings for SQLite
# Included by Makefile-phone and Makefile-mac

# --- Version ---
SQLITE_VER  = 3430200
SQLITE_YEAR = 2023
SQLITE_SHA256 = a17ac8792f57266847d57651c5259001d1e4e4b46be96ec0d985c953925b2a1c

# --- Toolchain Paths ---
include $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../altivec_toolchains.mk)
BIN_DIR = $(MODERN_BIN)

# --- Deployment Targets ---
MAC_MIN_PPC   = 10.4
MAC_MIN_X86   = 10.4
MAC_MIN_X64   = 10.9
MAC_MIN_ARM64 = 11.0
IOS_MIN_VER   = 5.0
IOS_ARM64_MIN_VER = 7.0

# --- Flags ---
OPT_FLAGS        = -O2
LEGACY_GCC_FLAGS = -fno-stack-protector -fno-common -fno-zero-initialized-in-bss -fPIC

# SQLite compile-time options
# OMIT_LOAD_EXTENSION: avoids -ldl linkage requirement for static builds
# HAVE_USLEEP: enables proper sleep in busy-wait (available on Tiger+)
SQLITE_CFLAGS = \
  -DSQLITE_THREADSAFE=1 \
  -DSQLITE_OMIT_LOAD_EXTENSION=1 \
  -DHAVE_USLEEP=1

# Legacy GCC (ppc/x86) doesn't have stdatomic.h — disable to avoid compile errors
LEGACY_SQLITE_CFLAGS = $(SQLITE_CFLAGS) -DHAVE_STDATOMIC_H=0

JOBS = $(shell getconf _NPROCESSORS_ONLN)

# Try each checksum-verified source independently before moving to its mirror.
SOURCE_DOWNLOAD_ATTEMPTS = 3
CURL_DOWNLOAD_FLAGS = --fail --silent --show-error --location \
                      --proto '=https' --proto-redir '=https' \
                      --connect-timeout 30

define download_to_target
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
	    echo "  > verified cached archive: $@"; \
	    exit 0; \
	  fi; \
	  echo " [!] Discarding cached archive with an invalid checksum: $@" >&2; \
	  rm -f "$@"; \
	fi; \
	for url in $(1); do \
	  attempt=1; \
	  while test "$$attempt" -le "$(SOURCE_DOWNLOAD_ATTEMPTS)"; do \
	    tmp="$$(mktemp "$@.tmp.XXXXXX")"; \
	    echo "  > downloading $$url (attempt $$attempt/$(SOURCE_DOWNLOAD_ATTEMPTS))"; \
	    if curl $(CURL_DOWNLOAD_FLAGS) "$$url" -o "$$tmp"; then \
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
	    if test "$$attempt" -lt "$(SOURCE_DOWNLOAD_ATTEMPTS)"; then \
	      sleep "$$((attempt * 2))"; \
	    fi; \
	    attempt="$$((attempt + 1))"; \
	  done; \
	done; \
	echo " [!] ERROR: failed to download and verify $@" >&2; \
	exit 1
endef

# Re-run the recipe so a cached archive is checksum-verified before use.
force-download-check:

.PHONY: force-download-check
