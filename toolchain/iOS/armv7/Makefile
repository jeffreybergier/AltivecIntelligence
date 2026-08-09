SHELL := /bin/bash

.DEFAULT_GOAL := release

PROJECT_NAME := AltivecToolchain
LLVM_VERSION := 15.0.6
DEPLOYMENT_TARGET ?= 6.0
# Use the CPUs visible to the current container or host by default. A
# command-line override such as `make JOBS=6` still takes precedence.
JOBS ?= $(shell nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || printf '%s\n' 2)
GENERATOR ?= auto

SDK ?= /osxcross/target/SDK/iPhoneOS8.4.sdk
CCTOOLS_BIN ?= /osxcross/target/bin
MACOS_COMPAT_SDK ?= /osxcross/legacy/target/SDK/MacOSX10.5.sdk
LDID ?= ldid
FAKEROOT ?= fakeroot
DPKG_DEB ?= dpkg-deb
DEVICE ?= koolphone5

BUILD_DIR := build-release
INTERMEDIATES_DIR := $(BUILD_DIR)/Intermediates
ARCHIVES_DIR := $(abspath $(INTERMEDIATES_DIR)/Archives)
HELPERS_DIR := helpers
COMMON_HELPERS_DIR := ../common/helpers
LLVM_WORK_DIR := $(abspath $(INTERMEDIATES_DIR)/llvm15-armv7)
LLVM_SOURCES_DIR := $(LLVM_WORK_DIR)/sources
LLVM_BUILD_ENGINE := $(HELPERS_DIR)/build-llvm15-ios.sh
LLVM_PACKAGE_SCRIPT := $(HELPERS_DIR)/llvm-package.sh
LLVM_PATCH := $(HELPERS_DIR)/llvm15-ios-clonefile.patch
LLVM_ARCLITE_ARCHIVE := payload/lib/arc/libarclite_iphoneos.a
LLVM_PACKAGE_NAME := clang-$(LLVM_VERSION)-armv7-apple-ios$(DEPLOYMENT_TARGET)
LLVM_PACKAGE_ARCHIVE := $(LLVM_WORK_DIR)/artifacts/$(LLVM_PACKAGE_NAME).tar.gz

CORE_TOOLS_WORK_DIR := $(abspath $(INTERMEDIATES_DIR)/core-tools-armv7)
CORE_TOOLS_BUILD_ENGINE := $(HELPERS_DIR)/build-core-tools.sh
CORE_TOOLS_EXTRA_BUILD_ENGINE := $(HELPERS_DIR)/build-extra-tools.sh
CORE_TOOLS_PACKAGE_SCRIPT := $(HELPERS_DIR)/core-tools-package.sh
CORE_TOOLS_CCTOOLS_PATCH := $(HELPERS_DIR)/cctools-ld64-armv7-atomic-alignment.patch
CORE_TOOLS_CCTOOLS_IOS43_PATCH := $(HELPERS_DIR)/cctools-ld64-ios43-deployment-floor.patch
CORE_TOOLS_IMAGEMAGICK_PATCH := $(HELPERS_DIR)/imagemagick-ios-target-conditionals.patch
CORE_TOOLS_MAKE_PATCH := $(HELPERS_DIR)/make-ios-portable-ar-header.patch
CORE_TOOLS_PS_PATCH := $(HELPERS_DIR)/adv-cmds-ps-ios-workqueue.patch
CORE_TOOLS_MANDOC_CONFIG := $(HELPERS_DIR)/mandoc-ios-configure.local.in
CORE_TOOLS_IMAGEMAGICK_POLICY := $(HELPERS_DIR)/imagemagick-policy.xml
CORE_TOOLS_IMAGEMAGICK_DELEGATES := $(HELPERS_DIR)/imagemagick-delegates.xml
CORE_TOOLS_PROFILE_SCRIPT := $(COMMON_HELPERS_DIR)/altivec-profile.sh
CORE_TOOLS_PROFILE_REL := etc/profile.d/altivec.sh
CORE_TOOLS_SOURCES_DIR := $(CORE_TOOLS_WORK_DIR)/sources
# /var is the stable Cydia-facing spelling on both iOS 6 and iOS 8; the OS
# resolves it onto the writable data partition at /private/var.
INSTALL_PREFIX := /var/altivec
INSTALL_PREFIX_TAG := $(subst /,-,$(patsubst /%,%,$(INSTALL_PREFIX)))
CORE_TOOLS_CC ?= /usr/bin/clang-18
CORE_TOOLS_CXX ?= /usr/bin/clang++-18
CORE_TOOLS_PACKAGE_NAME := altivec-toolchain-core-tools-armv7-ios$(DEPLOYMENT_TARGET)-$(INSTALL_PREFIX_TAG)
CORE_TOOLS_PACKAGE_ARCHIVE := $(CORE_TOOLS_WORK_DIR)/artifacts/$(CORE_TOOLS_PACKAGE_NAME).tar.gz

DEB_PACKAGE_ID ?= com.altivecintelligence.toolchain
DEB_NAME ?= Altivec Toolchain (armv7)
DEB_VERSION ?= 1.0.3
DEB_ARCH ?= iphoneos-arm
DEB_SECTION ?= Development
DEB_PRIORITY ?= optional
DEB_MAINTAINER ?= Altivec Intelligence <support@altivecintelligence.com>
DEB_DESCRIPTION ?= LLVM/Clang compiler plus linker, SDK, static-library and app-project managers, reusable IPA build rules, shell, process, network, database, archive, signing, and image tools for jailbroken armv7 iPhones.
DEB_DEPENDS ?= firmware (>= $(DEPLOYMENT_TARGET)), openssh, profile.d
DEB_CONFLICTS ?= com.altivecintelligence.altivecchain, com.altivecintelligence.altivecchain.coretools
DEB_REPLACES ?= com.altivecintelligence.altivecchain, com.altivecintelligence.altivecchain.coretools
DEB_COMPRESSION ?= gzip
DEB_STAGE := $(abspath $(INTERMEDIATES_DIR)/deb-root)
DEB_EXTRACT_DIR := $(abspath $(INTERMEDIATES_DIR)/deb-payload)
DEB_PACKAGE_SCRIPT := $(HELPERS_DIR)/deb.sh
SDK_MANAGER_SCRIPT := $(COMMON_HELPERS_DIR)/altivec-sdk.sh
SDK_CATALOG := $(COMMON_HELPERS_DIR)/iphoneos-sdk-catalog.json
SDK_MANAGER_CHECK := $(COMMON_HELPERS_DIR)/sdk-manager-check.sh
LIB_MANAGER_SCRIPT := $(HELPERS_DIR)/altivec-lib.sh
LIB_MANAGER_CHECK := $(HELPERS_DIR)/lib-manager-check.sh
IOS_APP_MAKEFILE := payload/share/altivec/make/ios-app.mk
IOS_APP_TEMPLATE_DIR := payload/share/altivec/templates/ios-app
IOS_APP_TEMPLATE_FILES := $(shell find "$(IOS_APP_TEMPLATE_DIR)" -type f -print)
IOS_APP_TOOL := $(COMMON_HELPERS_DIR)/altivec-app.sh
IOS_APP_MAKE_CHECK := $(HELPERS_DIR)/ios-app-make-check.sh
DEVICE_SMOKE_TEST := $(HELPERS_DIR)/device-smoke-test.sh
DEVICE_TOOLS_SMOKE_TEST := $(HELPERS_DIR)/device-tools-smoke-test.sh
DEVICE_IOS_APP_SMOKE_TEST := $(HELPERS_DIR)/device-ios-app-smoke-test.sh
DEVICE_INSTALL := $(HELPERS_DIR)/device-install.sh
DEB_OUTPUT := $(BUILD_DIR)/$(PROJECT_NAME)_$(DEB_VERSION)_iOS-armv7.deb

# Each executable target below maps to helpers/<target>.sh. The thin LLVM and
# core-tools entrypoints select an action in the shared build engines.
LLVM_ACTION_TARGETS := llvm-build llvm-configure llvm-native llvm-source
CORE_TOOLS_ACTION_TARGETS := \
	core-tools-build \
	core-tools-verify \
	core-tools-package-from-cache \
	core-tools-cctools \
	core-tools-libplist \
	core-tools-openssl \
	core-tools-ldid \
	core-tools-zip \
	core-tools-unzip \
	core-tools-zlib \
	core-tools-curl \
	core-tools-git \
	core-tools-libpng \
	core-tools-libjpeg \
	core-tools-imagemagick \
	core-tools-make \
	core-tools-file \
	core-tools-awk \
	core-tools-patch \
	core-tools-jq \
	core-tools-xz \
	core-tools-sqlite \
	core-tools-extra \
	core-tools-source

define run_llvm_target
"$(HELPERS_DIR)/$(1).sh" \
	--work-dir "$(LLVM_WORK_DIR)" \
	--allow-in-repo-work-dir \
	--archives-dir "$(ARCHIVES_DIR)" \
	--sources-dir "$(LLVM_SOURCES_DIR)" \
	--sdk "$(SDK)" \
	--cctools-bin "$(CCTOOLS_BIN)" \
	--deployment-target "$(DEPLOYMENT_TARGET)" \
	--jobs "$(JOBS)" \
	--generator "$(GENERATOR)" \
	--ldid "$(LDID)"
endef

define run_core_tools_target
"$(HELPERS_DIR)/$(1).sh" \
	--work-dir "$(CORE_TOOLS_WORK_DIR)" \
	--archives-dir "$(ARCHIVES_DIR)" \
	--sources-dir "$(CORE_TOOLS_SOURCES_DIR)" \
	--sdk "$(SDK)" \
	--macos-compat-sdk "$(MACOS_COMPAT_SDK)" \
	--cctools-bin "$(CCTOOLS_BIN)" \
	--deployment-target "$(DEPLOYMENT_TARGET)" \
	--jobs "$(JOBS)" \
	--prefix "$(INSTALL_PREFIX)" \
	--cc "$(CORE_TOOLS_CC)" \
	--cxx "$(CORE_TOOLS_CXX)" \
	--ldid "$(LDID)"
endef

define run_deb_action
@AT_PROJECT_ROOT="$(CURDIR)" \
	AT_INTERMEDIATES_DIR="$(abspath $(INTERMEDIATES_DIR))" \
	AT_STAGE_DIR="$(DEB_STAGE)" \
	AT_EXTRACT_DIR="$(DEB_EXTRACT_DIR)" \
	AT_LLVM_ARCHIVE="$(LLVM_PACKAGE_ARCHIVE)" \
	AT_LLVM_PACKAGE_NAME="$(LLVM_PACKAGE_NAME)" \
	AT_LLVM_VERSION="$(LLVM_VERSION)" \
	AT_CORE_ARCHIVE="$(CORE_TOOLS_PACKAGE_ARCHIVE)" \
	AT_CORE_PACKAGE_NAME="$(CORE_TOOLS_PACKAGE_NAME)" \
	AT_INSTALL_PREFIX="$(INSTALL_PREFIX)" \
	AT_PROFILE_SCRIPT="$(CORE_TOOLS_PROFILE_SCRIPT)" \
	AT_PROFILE_REL="$(CORE_TOOLS_PROFILE_REL)" \
	AT_SDK_MANAGER_SCRIPT="$(SDK_MANAGER_SCRIPT)" \
	AT_SDK_CATALOG="$(SDK_CATALOG)" \
	AT_LIB_MANAGER_SCRIPT="$(LIB_MANAGER_SCRIPT)" \
	AT_IOS_APP_MAKEFILE="$(IOS_APP_MAKEFILE)" \
	AT_IOS_APP_TEMPLATE_DIR="$(IOS_APP_TEMPLATE_DIR)" \
	AT_IOS_APP_TOOL="$(IOS_APP_TOOL)" \
	AT_OUTPUT="$(abspath $(DEB_OUTPUT))" \
	AT_PACKAGE_ID="$(DEB_PACKAGE_ID)" \
	AT_DISPLAY_NAME="$(DEB_NAME)" \
	AT_VERSION="$(DEB_VERSION)" \
	AT_ARCH="$(DEB_ARCH)" \
	AT_SECTION="$(DEB_SECTION)" \
	AT_PRIORITY="$(DEB_PRIORITY)" \
	AT_MAINTAINER="$(DEB_MAINTAINER)" \
	AT_DESCRIPTION="$(DEB_DESCRIPTION)" \
	AT_DEPENDS="$(DEB_DEPENDS)" \
	AT_CONFLICTS="$(DEB_CONFLICTS)" \
	AT_REPLACES="$(DEB_REPLACES)" \
	AT_COMPRESSION="$(DEB_COMPRESSION)" \
	AT_FAKEROOT="$(FAKEROOT)" \
	AT_DPKG_DEB="$(DPKG_DEB)" \
	"$(DEB_PACKAGE_SCRIPT)"
endef

.PHONY: release sources deb deb-from-cache llvm-package $(LLVM_ACTION_TARGETS)
.PHONY: core-tools-package $(CORE_TOOLS_ACTION_TARGETS) core-tools-check
.PHONY: sdk-manager-check lib-manager-check ios-app-make-check
.PHONY: check install device-smoke-test device-tools-smoke-test device-ios-app-smoke-test clean help

# Fetch and verify every source before starting either compilation pipeline.
sources:
	+$(MAKE) --no-print-directory core-tools-source
	+$(MAKE) --no-print-directory llvm-source

# Keep LLVM compilation last in a full release even when the outer make uses
# -j. The packaging-only deb target runs after both payload archives exist.
release: sources
	+$(MAKE) --no-print-directory core-tools-package
	+$(MAKE) --no-print-directory llvm-package
	+$(MAKE) --no-print-directory deb

# Repackage the cached LLVM and core-tools archives without entering either
# compilation pipeline. This is useful for metadata and layout-only changes.
deb: $(DEB_PACKAGE_SCRIPT) $(CORE_TOOLS_PROFILE_SCRIPT) \
		$(SDK_MANAGER_SCRIPT) $(SDK_CATALOG) \
		$(LIB_MANAGER_SCRIPT) \
		$(IOS_APP_MAKEFILE) $(IOS_APP_TOOL) $(IOS_APP_TEMPLATE_FILES) | \
		sdk-manager-check lib-manager-check ios-app-make-check
	@test -f "$(LLVM_PACKAGE_ARCHIVE)" || { echo "error: cached LLVM archive is missing: $(LLVM_PACKAGE_ARCHIVE)" >&2; exit 1; }
	@test -f "$(CORE_TOOLS_PACKAGE_ARCHIVE)" || { echo "error: cached core-tools archive is missing: $(CORE_TOOLS_PACKAGE_ARCHIVE)" >&2; exit 1; }
	$(call run_deb_action)

deb-from-cache: deb

llvm-package: $(LLVM_PACKAGE_ARCHIVE)

$(LLVM_ACTION_TARGETS): %: $(HELPERS_DIR)/%.sh
	@mkdir -p "$(INTERMEDIATES_DIR)"
	$(call run_llvm_target,$@)

core-tools-package: $(CORE_TOOLS_PACKAGE_ARCHIVE)

$(CORE_TOOLS_ACTION_TARGETS): %: $(HELPERS_DIR)/%.sh | core-tools-check
	@mkdir -p "$(INTERMEDIATES_DIR)"
	$(call run_core_tools_target,$@)

check: $(HELPERS_DIR)/check.sh
	@"$(HELPERS_DIR)/$@.sh" \
		--sdk "$(SDK)" \
		--cctools-bin "$(CCTOOLS_BIN)" \
		--ldid "$(LDID)" \
		--fakeroot "$(FAKEROOT)" \
		--dpkg-deb "$(DPKG_DEB)"

core-tools-check: $(HELPERS_DIR)/core-tools-check.sh
	@"$(HELPERS_DIR)/$@.sh" \
		--sdk "$(SDK)" \
		--macos-compat-sdk "$(MACOS_COMPAT_SDK)" \
		--cctools-bin "$(CCTOOLS_BIN)" \
		--cc "$(CORE_TOOLS_CC)" \
		--cxx "$(CORE_TOOLS_CXX)" \
		--ldid "$(LDID)" \
		--fakeroot "$(FAKEROOT)" \
		--dpkg-deb "$(DPKG_DEB)"

sdk-manager-check: $(SDK_MANAGER_CHECK) $(SDK_MANAGER_SCRIPT) $(SDK_CATALOG)
	@"$(SDK_MANAGER_CHECK)" "$(SDK_MANAGER_SCRIPT)" "$(SDK_CATALOG)"

lib-manager-check: $(LIB_MANAGER_CHECK) $(LIB_MANAGER_SCRIPT)
	@"$(LIB_MANAGER_CHECK)" "$(LIB_MANAGER_SCRIPT)"

ios-app-make-check: $(IOS_APP_MAKE_CHECK) $(IOS_APP_MAKEFILE) \
		$(IOS_APP_TOOL) $(IOS_APP_TEMPLATE_FILES)
	@"$(IOS_APP_MAKE_CHECK)" "$(IOS_APP_MAKEFILE)" \
		"$(IOS_APP_TEMPLATE_DIR)" "$(IOS_APP_TOOL)"

install: $(DEVICE_INSTALL)
	@"$(DEVICE_INSTALL)" \
		--device "$(DEVICE)" \
		--deb "$(abspath $(DEB_OUTPUT))" \
		--package-id "$(DEB_PACKAGE_ID)" \
		--version "$(DEB_VERSION)" \
		--arch "$(DEB_ARCH)" \
		--dpkg-deb "$(DPKG_DEB)"

device-smoke-test: $(DEVICE_SMOKE_TEST)
	@"$(DEVICE_SMOKE_TEST)" "$(DEVICE)"

device-tools-smoke-test: $(DEVICE_TOOLS_SMOKE_TEST)
	@"$(DEVICE_TOOLS_SMOKE_TEST)" "$(DEVICE)"

device-ios-app-smoke-test: $(DEVICE_IOS_APP_SMOKE_TEST)
	@"$(DEVICE_IOS_APP_SMOKE_TEST)" "$(DEVICE)"

$(LLVM_PACKAGE_ARCHIVE): $(LLVM_BUILD_ENGINE) $(LLVM_PATCH) \
		$(LLVM_ARCLITE_ARCHIVE) | check $(LLVM_PACKAGE_SCRIPT)
	@mkdir -p "$(INTERMEDIATES_DIR)"
	$(call run_llvm_target,llvm-package)
	@test -f "$@" || { echo "error: LLVM package was not created: $@" >&2; exit 1; }

$(CORE_TOOLS_PACKAGE_ARCHIVE): $(CORE_TOOLS_BUILD_ENGINE) \
		$(CORE_TOOLS_EXTRA_BUILD_ENGINE) \
		$(CORE_TOOLS_CCTOOLS_PATCH) \
		$(CORE_TOOLS_CCTOOLS_IOS43_PATCH) \
		$(CORE_TOOLS_IMAGEMAGICK_PATCH) \
		$(CORE_TOOLS_MAKE_PATCH) \
		$(CORE_TOOLS_PS_PATCH) \
		$(CORE_TOOLS_MANDOC_CONFIG) \
		$(CORE_TOOLS_IMAGEMAGICK_POLICY) \
		$(CORE_TOOLS_IMAGEMAGICK_DELEGATES) | core-tools-check $(CORE_TOOLS_PACKAGE_SCRIPT)
	@mkdir -p "$(INTERMEDIATES_DIR)"
	$(call run_core_tools_target,core-tools-package)
	@test -f "$@" || { echo "error: core-tools package was not created: $@" >&2; exit 1; }

clean: $(HELPERS_DIR)/clean.sh
	@"$(HELPERS_DIR)/$@.sh" \
		--project-root "$(CURDIR)" \
		--build-dir "$(abspath $(BUILD_DIR))"

help:
	@printf '%s\n' \
		'Targets:' \
		'  release         Fetch all sources, compile LLVM last, then create the combined .deb (default).' \
		'  sources         Download, verify, and extract every toolchain source without compiling.' \
		'  deb             Repackage cached LLVM/Core Tools payloads without compiling.' \
		'  deb-from-cache  Alias for deb.' \
		'  llvm-package    Build the signed relocatable LLVM/Clang archive.' \
		'  llvm-build      Build Clang without staging an archive.' \
		'  llvm-configure  Download/bootstrap and configure the ARMv7 build.' \
		'  llvm-native     Build the native TableGen bootstrap tools.' \
		'  llvm-source     Download, verify, extract, and patch LLVM source.' \
		'  core-tools-package  Build the signed core-tools payload archive.' \
		'  core-tools-package-from-cache  Reassemble it from existing component stages without compiling.' \
		'  core-tools-build    Build and stage the core tools without a .deb.' \
		'  core-tools-verify   Rebuild, stage, and verify every phone binary.' \
		'  core-tools-cctools  Build cctools and ld64 only.' \
		'  core-tools-libplist Build libplist and plistutil only.' \
		'  core-tools-openssl  Build the OpenSSL CLI and private static libraries.' \
		'  core-tools-ldid     Build ldid and its dependencies only.' \
		'  core-tools-zip      Build Info-ZIP zip only.' \
		'  core-tools-unzip    Build Info-ZIP unzip only.' \
		'  core-tools-zlib     Build the private static zlib dependency.' \
		'  core-tools-curl     Build curl/OpenSSL with the bundled CA roots.' \
		'  core-tools-git      Build Git with SSH and HTTPS transports.' \
		'  core-tools-libpng   Build the private static PNG delegate.' \
		'  core-tools-libjpeg  Build the private static JPEG delegate.' \
		'  core-tools-imagemagick Build ImageMagick Q8 with PNG/JPEG.' \
		'  core-tools-make     Build GNU Make 4.4.1.' \
		'  core-tools-file     Build file/libmagic 5.48.' \
		'  core-tools-awk      Build One True Awk 20260426.' \
		'  core-tools-patch    Build GNU patch 2.8.' \
		'  core-tools-jq       Build jq 1.8.2.' \
		'  core-tools-xz       Build XZ Utils 5.8.3 (xz/unxz/xzcat).' \
		'  core-tools-sqlite   Build SQLite 3.43.2 CLI/library.' \
		'  core-tools-extra    Build approved shell/process/network/manual tools (netstat deferred).' \
		'  core-tools-source   Download and verify pinned core-tool sources.' \
		'  check           Validate tools, SDK, and linker paths.' \
		'  core-tools-check Validate the core-tools build prerequisites.' \
		'  sdk-manager-check Validate the SDK manager and pinned catalog.' \
		'  lib-manager-check Validate the GitHub static-library manager.' \
		'  ios-app-make-check Validate the IPA rules, initializer, and complete app template.' \
		'  install         Install the existing .deb over SSH (DEVICE=koolphone5; never rebuilds).' \
		'  device-smoke-test Test installed linker and ImageMagick commands over SSH (DEVICE=koolphone5).' \
		'  device-tools-smoke-test Test every packaged command and alias over SSH (DEVICE=koolphone5).' \
		'  device-ios-app-smoke-test Build, analyze, inspect, and clean a sample IPA over SSH.' \
		'  clean           Remove build-release.' \
		'' \
		'Executable targets map to helpers/<target>.sh.' \
		'All generated build state goes under build-release/Intermediates.' \
		'Downloaded source archives are stored under $(ARCHIVES_DIR).' \
		'Extracted sources remain in their component directories under Intermediates.' \
		'The finished installer is $(DEB_OUTPUT).' \
		'This package contains Clang and its resource headers, not a complete iOS SDK.'
