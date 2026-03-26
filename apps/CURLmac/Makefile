# Altivec Intelligence - CURLmac (Mac)
APP_NAME = CURLmac
RES_DIR = Resources
INFO_PLIST = Info.plist
SOURCES = main.m AppDelegate.m

CURL_DIR = /repo/altivec/libs/libcurl/build-mac
EXTRA_CFLAGS = -I$(CURL_DIR)/include
# These are used for targets that don't have overrides
EXTRA_LIBS = -L$(CURL_DIR)/lib -lcurl_static -lssl_static -lcrypto_static -lz_static -lpthread -ldl -framework SystemConfiguration -lldap -llber

# Import common Mac build engine
include ../../altivec_common_mac.mk

# Final Boss Target: Quad-Fat (ppc, x86, x64, arm64)
quad: $(BUNDLE)

# Override bundle to avoid dsymutil errors on legacy slices
$(BUNDLE): $(UNIVERSAL_BIN)
	@echo " [6/7] Building app package (QUAD-FAT)..."
	@mkdir -p $@/Contents/MacOS $@/Contents/Resources
	@echo "  > copying binary"
	@cp $< $@/Contents/MacOS/$(APP_NAME)
	@echo "  > copying Info.plist"
	@cp $(INFO_PLIST) $@/Contents/Info.plist
	@if [ -d "$(RES_DIR)" ] && [ "$$(ls -A $(RES_DIR) 2>/dev/null)" ]; then \
		echo "  > copying resources" ; \
		cp -R $(RES_DIR)/* $@/Contents/Resources/ ; \
	fi
	@echo "  > extracting symbols (x64, arm64)"
	@if [ -f "$(INT_DIR)/x64.bin" ]; then $(DSYMUTIL) $(INT_DIR)/x64.bin -o $(BUILD_DIR)/$(APP_NAME).x64.dSYM; fi
	@if [ -f "$(INT_DIR)/arm.bin" ]; then $(DSYMUTIL) $(INT_DIR)/arm.bin -o $(BUILD_DIR)/$(APP_NAME).arm.dSYM; fi
	@echo -n "APPL????" > $@/Contents/PkgInfo

# Override ppc link
$(INT_DIR)/ppc.bin: $(PPC_OBJS)
	@echo "  > linking ppc binary"
	@MACOSX_DEPLOYMENT_TARGET=10.4 $(COMPILER_PPC) -arch ppc -isysroot $(SDK_MAC_OLD_PATH) \
		-framework AppKit -lobjc $^ \
		$(CURL_DIR)/prefix/ppc/lib/libcurl.a \
		$(CURL_DIR)/prefix/ppc/lib/libssl.a \
		$(CURL_DIR)/prefix/ppc/lib/libcrypto.a \
		$(CURL_DIR)/prefix/ppc/lib/libz.a \
		-lpthread -ldl -framework SystemConfiguration -lldap -llber -o $@

# Override x86 link
$(INT_DIR)/x86.bin: $(X86_OBJS)
	@echo "  > linking x86 binary"
	@MACOSX_DEPLOYMENT_TARGET=10.4 $(COMPILER_X86) -arch i386 -isysroot $(SDK_MAC_OLD_PATH) \
		-framework AppKit -lobjc $^ \
		$(CURL_DIR)/prefix/x86/lib/libcurl.a \
		$(CURL_DIR)/prefix/x86/lib/libssl.a \
		$(CURL_DIR)/prefix/x86/lib/libcrypto.a \
		$(CURL_DIR)/prefix/x86/lib/libz.a \
		-lpthread -ldl -framework SystemConfiguration -lldap -llber -o $@

# Override x64 link using modern ld64.lld and a stub for missing runtime symbols
$(INT_DIR)/x64.bin: $(X64_OBJS) stubs.c
	@echo "  > linking x64 binary (ld64.lld)"
	@mkdir -p $(INT_DIR)/x64
	@$(COMPILER_X64) -target x86_64-apple-macos10.11 -c stubs.c -o $(INT_DIR)/x64/stubs.o
	@/osxcross/target/bin/ld64.lld -demangle -dynamic -arch x86_64 -platform_version macos 10.11.0 10.11.0 \
		-syslibroot $(SDK_MAC_MID_PATH) -o $@ \
		-L$(SDK_MAC_MID_PATH)/usr/lib \
		$(CURL_DIR)/prefix/x64/lib/libcurl.a \
		$(CURL_DIR)/prefix/x64/lib/libssl.a \
		$(CURL_DIR)/prefix/x64/lib/libcrypto.a \
		$(CURL_DIR)/prefix/x64/lib/libz.a \
		-lpthread -ldl -framework SystemConfiguration -lldap -llber \
		$(X64_OBJS) $(INT_DIR)/x64/stubs.o -lSystem -framework AppKit -lobjc $(SDK_MAC_MID_PATH)/usr/lib/crt1.10.6.o

$(INT_DIR)/arm.bin: $(ARM_OBJS)
	@echo "  > linking arm64 binary"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_NEW) $(COMPILER_ARM) -target arm64-apple-macos$(MAC_MIN_NEW) -isysroot $(SDK_MAC_NEW_PATH) \
		-fuse-ld=$(LD64_LLD) -Wl,-platform_version,macos,$(MAC_MIN_NEW),$(SDK_MAC_NEW) \
	    -framework AppKit -lobjc $^ \
		$(CURL_DIR)/prefix/arm64/lib/libcurl.a \
		$(CURL_DIR)/prefix/arm64/lib/libssl.a \
		$(CURL_DIR)/prefix/arm64/lib/libcrypto.a \
		$(CURL_DIR)/prefix/arm64/lib/libz.a \
		-lpthread -ldl -framework SystemConfiguration -lldap -llber -o $@

# Redefine universal_bin to merge ALL slices (Quad-Fat)
$(INT_DIR)/$(APP_NAME)-universal: $(INT_DIR)/ppc.bin $(INT_DIR)/x86.bin $(INT_DIR)/x64.bin $(INT_DIR)/arm.bin
	@echo " [5/7] Merging QUAD-FAT binary (ppc, x86, x64, arm64)..."
	@lipo -create $^ -output $@

# Append flags
COMMON_CFLAGS += $(EXTRA_CFLAGS)
