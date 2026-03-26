# AltivecIntelligence Common Build Settings for libcurl
# Included by Makefile-phone and Makefile-mac

# --- Toolchain Paths ---
OSXCROSS_ROOT=/osxcross/target
BIN_DIR=$(OSXCROSS_ROOT)/bin
SDK_DIR=$(OSXCROSS_ROOT)/SDK

# --- Compilers ---
COMPILER_PPC=oppc32-gcc
COMPILER_X86=o32-gcc
COMPILER_X64=x86_64-apple-darwin15-clang
COMPILER_ARM64=/usr/bin/clang
COMPILER_IOS=/usr/bin/clang

# --- SDK Paths ---
SDK_PPC_PATH=$(SDK_DIR)/MacOSX10.5.sdk
SDK_X86_PATH=$(SDK_DIR)/MacOSX10.5.sdk
SDK_X64_PATH=$(SDK_DIR)/MacOSX10.11.sdk
SDK_ARM64_PATH=$(SDK_DIR)/MacOSX11.3.sdk
SDK_IOS_PATH=$(SDK_DIR)/iPhoneOS8.4.sdk

# --- Cross Tools ---
# Use darwin9 tools for legacy slices (PPC, X86, i8-armv7)
AR_LEGACY=$(BIN_DIR)/i386-apple-darwin9-ar
RANLIB_LEGACY=$(BIN_DIR)/i386-apple-darwin9-ranlib
# Use modern tools for modern slices (X64, ARM64 Mac, i8-arm64)
AR_MODERN=/usr/bin/llvm-ar
RANLIB_MODERN=/usr/bin/llvm-ranlib

LIPO=$(BIN_DIR)/i386-apple-darwin9-lipo
LIBTOOL=$(BIN_DIR)/i386-apple-darwin9-libtool
LD64_LLD=$(BIN_DIR)/ld64.lld

# --- Standard Flags ---
OPT_FLAGS=-O2
COMMON_WARN_FLAGS=-Wall -Wimplicit-function-declaration

# --- Deployment Targets ---
MAC_MIN_PPC=10.4
MAC_MIN_X86=10.4
MAC_MIN_X64=10.6
MAC_MIN_ARM64=11.0
IOS_MIN_VER=4.3

# PPC specific flags from altivec_common_mac.mk
PPC_COMPAT_FLAGS=-fno-stack-protector -fno-common -fno-zero-initialized-in-bss

# Jobs for parallel make
JOBS=$(shell getconf _NPROCESSORS_ONLN)
