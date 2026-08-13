# AltivecIntelligence Common Build Settings for AltivecCore
# Included by Makefile-phone and Makefile-mac

# --- Toolchain Paths ---
include $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../altivec_toolchains.mk)
BIN_DIR=$(MODERN_BIN)

# --- Standard Flags ---
OPT_FLAGS=-O3
COMMON_WARN_FLAGS=-Wall -Wimplicit-function-declaration
LEGACY_GCC_FLAGS=-fno-stack-protector -fno-common -fno-zero-initialized-in-bss -fPIC

# --- Deployment Targets ---
MAC_MIN_PPC=10.4
MAC_MIN_X86=10.4
MAC_MIN_X64=10.9
MAC_MIN_ARM64=11.0
IOS_MIN_VER=5.0
IOS_ARM64_MIN_VER=7.0

JOBS=$(shell getconf _NPROCESSORS_ONLN)

plist_version = $(shell python3 -c 'import plistlib; print(plistlib.load(open("$(1)", "rb"))["CFBundleVersion"])')
