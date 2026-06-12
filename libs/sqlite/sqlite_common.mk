# AltivecIntelligence Common Build Settings for SQLite
# Included by Makefile-phone and Makefile-mac

# --- Version ---
SQLITE_VER  = 3430200
SQLITE_YEAR = 2023

# --- Toolchain Paths ---
OSXCROSS_ROOT = /osxcross/target
BIN_DIR       = $(OSXCROSS_ROOT)/bin
SDK_DIR       = $(OSXCROSS_ROOT)/SDK

# --- Compilers ---
COMPILER_PPC   = oppc32-gcc
COMPILER_X86   = o32-gcc
COMPILER_X64   = /usr/bin/clang
COMPILER_ARM64 = /usr/bin/clang
COMPILER_IOS   = /usr/bin/clang

# --- SDK Paths ---
SDK_PPC_PATH   = $(SDK_DIR)/MacOSX10.5.sdk
SDK_X86_PATH   = $(SDK_DIR)/MacOSX10.5.sdk
SDK_X64_PATH   = $(SDK_DIR)/MacOSX11.3.sdk
SDK_ARM64_PATH = $(SDK_DIR)/MacOSX11.3.sdk
SDK_IOS_PATH   = $(SDK_DIR)/iPhoneOS8.4.sdk

# --- Archive Tools ---
AR_LEGACY     = $(BIN_DIR)/i386-apple-darwin9-ar
RANLIB_LEGACY = $(BIN_DIR)/i386-apple-darwin9-ranlib
LIPO          = $(BIN_DIR)/i386-apple-darwin9-lipo

AR_MODERN     = /usr/bin/llvm-ar-14
RANLIB_MODERN = /usr/bin/llvm-ranlib-14
LIPO_MODERN   = /usr/bin/llvm-lipo-14

LD64_LLD = $(BIN_DIR)/ld64.lld

# --- Deployment Targets ---
MAC_MIN_PPC   = 10.4
MAC_MIN_X86   = 10.4
MAC_MIN_X64   = 10.9
MAC_MIN_ARM64 = 11.0
IOS_MIN_VER   = 4.3
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
