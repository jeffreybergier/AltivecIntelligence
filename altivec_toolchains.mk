# Shared paths for Altivec's isolated modern and legacy toolchains.

ALTIVEC_MODERN_TOOLCHAIN ?= /osxcross/modern
ALTIVEC_LEGACY_TOOLCHAIN ?= /osxcross/legacy/target

MODERN_BIN ?= $(ALTIVEC_MODERN_TOOLCHAIN)/bin
LEGACY_BIN ?= $(ALTIVEC_LEGACY_TOOLCHAIN)/bin
MODERN_SDK_DIR ?= $(ALTIVEC_MODERN_TOOLCHAIN)/SDK
LEGACY_SDK_DIR ?= $(ALTIVEC_LEGACY_TOOLCHAIN)/SDK

COMPILER_PPC ?= $(LEGACY_BIN)/oppc32-gcc
COMPILER_X86 ?= $(LEGACY_BIN)/o32-gcc
COMPILER_X64 ?= $(firstword $(wildcard $(MODERN_BIN)/x86_64-apple-darwin*-clang))
COMPILER_ARM64 ?= $(firstword $(wildcard $(MODERN_BIN)/arm64-apple-darwin*-clang))
COMPILER_IOS ?= /usr/bin/clang

SDK_PPC_PATH ?= $(LEGACY_SDK_DIR)/MacOSX10.5.sdk
SDK_X86_PATH ?= $(LEGACY_SDK_DIR)/MacOSX10.5.sdk
SDK_X64_PATH ?= $(MODERN_SDK_DIR)/MacOSX11.3.sdk
SDK_ARM64_PATH ?= $(MODERN_SDK_DIR)/MacOSX11.3.sdk
SDK_IOS_PATH ?= $(MODERN_SDK_DIR)/iPhoneOS8.4.sdk

AR_LEGACY ?= $(LEGACY_BIN)/i386-apple-darwin9-ar
RANLIB_LEGACY ?= $(LEGACY_BIN)/i386-apple-darwin9-ranlib
LIBTOOL_LEGACY ?= $(LEGACY_BIN)/i386-apple-darwin9-libtool

AR_MODERN ?= $(MODERN_BIN)/ar
RANLIB_MODERN ?= $(MODERN_BIN)/ranlib
LIBTOOL_MODERN ?= $(MODERN_BIN)/libtool
LIPO_MODERN ?= $(MODERN_BIN)/lipo
NM ?= $(MODERN_BIN)/nm
MODERN_LD ?= $(MODERN_BIN)/ld
# Current Apple ld64 omits CPU_SUBTYPE_LIB64 from x86_64 Mach-O headers,
# causing Tiger on 64-bit-capable Intel CPUs to select that incompatible slice
# instead of i386. LLVM's Mach-O linker retains the legacy capability bit.
LD64_LLD ?= /usr/bin/ld64.lld-18

# The legacy lipo is retained for final quad-fat assembly because it is the
# member of the pair explicitly built with PowerPC support.
LIPO ?= $(LEGACY_BIN)/i386-apple-darwin9-lipo
LIBTOOL ?= $(LEGACY_BIN)/i386-apple-darwin9-libtool
DSYMUTIL ?= /usr/bin/dsymutil
