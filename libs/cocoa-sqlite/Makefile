# Optional SQLite library; no dependency from basic AltivecCocoa consumers.
.DEFAULT_GOAL := all
CWD := $(CURDIR)
include ../cocoa/cocoa_common.mk
SOURCES = ai_store.c ai_query.c AIStoreObserver.m
HEADERS = ai_store.h ai_query.h AIStoreObserver.h AltivecCocoaSQLite.h
all: mac phone
mac: build-mac/lib/libAltivecCocoaSQLite.a build-mac/include/.stamp
phone: build-phone/lib/libAltivecCocoaSQLite.a build-phone/include/.stamp

build-%/include/.stamp: $(HEADERS)
	mkdir -p $(@D)/AltivecCocoaSQLite
	cp $(HEADERS) $(@D)/
	cp $(HEADERS) $(@D)/AltivecCocoaSQLite/
	touch $@

# Portable consumers use only C objects; Foundation is pulled in only by ObjC callers.
CC_ppc = $(COMPILER_PPC)
CC_i386 = $(COMPILER_X86)
CC_x86_64 = $(COMPILER_X64)
CC_arm64 = $(COMPILER_ARM64)
FLAGS_ppc = -arch ppc -mmacosx-version-min=10.4 -isysroot $(SDK_PPC_PATH) $(LEGACY_GCC_FLAGS)
FLAGS_i386 = -arch i386 -mmacosx-version-min=10.4 -isysroot $(SDK_X86_PATH) $(LEGACY_GCC_FLAGS)
FLAGS_x86_64 = -target x86_64-apple-macos10.9 -isysroot $(SDK_X64_PATH) -B$(BIN_DIR)
FLAGS_arm64 = -target arm64-apple-macos11.0 -isysroot $(SDK_ARM64_PATH) -B$(BIN_DIR)
CC_armv7 = $(COMPILER_IOS)
CC_ios64 = $(COMPILER_IOS)
FLAGS_armv7 = -target armv7-apple-ios5.0 -isysroot $(SDK_IOS_PATH) -B$(BIN_DIR)
FLAGS_ios64 = -target arm64-apple-ios7.0 -isysroot $(SDK_IOS_PATH) -B$(BIN_DIR)

define slice
build-$(1)/$(2)/libAltivecCocoaSQLite.a: $(addprefix build-$(1)/$(2)/,$(addsuffix .o,$(SOURCES)))
	$(AR_MODERN) rcs $$@ $$^
build-$(1)/$(2)/%.o: % $(HEADERS)
	mkdir -p $$(@D)
	$(CC_$(2)) $(FLAGS_$(2)) -O2 -Wall -Wextra $(if $(filter ppc i386,$(2)),,-Wno-semicolon-before-method-body) -I../core/build-$(1)/include -c $$< -o $$@
endef
$(foreach a,ppc i386 x86_64 arm64,$(eval $(call slice,mac,$(a))))
$(foreach a,armv7 ios64,$(eval $(call slice,phone,$(a))))
build-mac/lib/libAltivecCocoaSQLite.a: $(foreach a,ppc i386 x86_64 arm64,build-mac/$(a)/libAltivecCocoaSQLite.a)
	mkdir -p $(@D)
	$(LIPO_MODERN) -create $^ -output $@
build-phone/lib/libAltivecCocoaSQLite.a: $(foreach a,armv7 ios64,build-phone/$(a)/libAltivecCocoaSQLite.a)
	mkdir -p $(@D)
	$(LIPO_MODERN) -create $^ -output $@
.PHONY: all mac phone test

test:
	mkdir -p build-linux
	$(CC) -std=c99 -Wall -Wextra -Werror -I. tests/store_test.c ai_store.c ai_query.c -lsqlite3 -pthread -o build-linux/store_test
	./build-linux/store_test
