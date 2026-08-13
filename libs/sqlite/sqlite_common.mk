# AltivecIntelligence Common Build Settings for SQLite
# Included by Makefile-phone and Makefile-mac

# --- Version ---
SQLITE_VER  = 3430200
SQLITE_YEAR = 2023

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

# Network downloads are part of dependency bootstrapping. Use retries and a
# temporary output file so transient CDN errors do not leave corrupt archives.
CURL_RETRY_FLAGS = --fail --location --retry 5 --retry-delay 2 \
                   --retry-all-errors --connect-timeout 30

define download_to_target
	@set -e; \
	tmp="$@.tmp"; \
	rm -f "$$tmp"; \
	for url in $(1); do \
	  echo "  > downloading $$url"; \
	  if curl $(CURL_RETRY_FLAGS) "$$url" -o "$$tmp"; then \
	    mv "$$tmp" "$@"; \
	    exit 0; \
	  fi; \
	  rm -f "$$tmp"; \
	done; \
	echo " [!] ERROR: failed to download $@"; \
	exit 1
endef
