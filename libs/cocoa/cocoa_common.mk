# AltivecIntelligence Common Build Settings for AltivecCocoa
# Included by Makefile-mac.

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
IOS_MIN_VER=4.3
IOS_ARM64_MIN_VER=7.0

plist_version = $(shell python3 -c 'import plistlib; print(plistlib.load(open("$(1)", "rb"))["CFBundleVersion"])')
