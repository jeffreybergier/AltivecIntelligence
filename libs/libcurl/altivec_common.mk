# AltivecIntelligence Common Build Settings
# This file centralizes toolchain and SDK paths to ensure consistency across all builds.

# --- Toolchain Paths ---
OSXCROSS_ROOT=/osxcross/target
BIN_DIR=$(OSXCROSS_ROOT)/bin
SDK_DIR=$(OSXCROSS_ROOT)/SDK

# --- Compilers ---
CLANG3=o64-clang
GCC4=oppc32-gcc
CLANG14=/usr/bin/clang

# --- SDK Paths ---
MAC_SDK_PATH=$(SDK_DIR)/MacOSX10.6.sdk
TIGER_SDK_PATH=$(SDK_DIR)/MacOSX10.4u.sdk
IOS_SDK_PATH=$(SDK_DIR)/iPhoneOS8.2.sdk

# --- Cross Tools ---
AR=$(BIN_DIR)/x86_64-apple-darwin10-ar
RANLIB=$(BIN_DIR)/x86_64-apple-darwin10-ranlib
LIBTOOL=$(BIN_DIR)/x86_64-apple-darwin10-libtool
LIPO=$(BIN_DIR)/x86_64-apple-darwin10-lipo

# --- Standard Flags ---
OPT_FLAGS=-O2
COMMON_WARN_FLAGS=-Wall -Wimplicit-function-declaration
CLANG_WARN_FLAGS=-Wobjc-method-access -Wno-unused-command-line-argument -Wunguarded-availability

# --- Architecture & Compatibility Flags ---
# Mac Strategy: CLANG14 for x86_64, GCC4 for PPC
MAC_MIN_VER=10.5
MAC_X64_FLAGS=-target x86_64-apple-macosx$(MAC_MIN_VER) -isysroot $(MAC_SDK_PATH) -B$(BIN_DIR)
MAC_PPC_FLAGS=-mmacosx-version-min=$(MAC_MIN_VER) -isysroot $(MAC_SDK_PATH) -arch ppc -fobjc-abi-version=1

# iPhone Strategy: CLANG14 for arm64/armv7
IOS_MIN_VER=4.3
IOS_TARGET_FLAGS=-target arm64-apple-ios$(IOS_MIN_VER) -isysroot $(IOS_SDK_PATH) -B$(BIN_DIR)

# Combined CFLAGS for convenience
CFLAGS_COMMON=$(OPT_FLAGS) $(COMMON_WARN_FLAGS)

# Jobs for parallel make
JOBS=$(shell getconf _NPROCESSORS_ONLN)
