# Altivec Intelligence - CURLphone (iPhone)
APP_NAME = CURLphone
SOURCES = main.m AppDelegate.m
INFO_PLIST = Info.plist

CURL_DIR = ../../libs/libcurl/build-phone
EXTRA_FLAGS = -I$(CURL_DIR)/include
EXTRA_LIBS = -L$(CURL_DIR)/lib -lAICURLConnection -lcurl -lssl -lcrypto -lz -lresolv

# Import common iPhone build engine
include ../../altivec_common_phone.mk

# Override/Append
IOS_FLAGS += $(EXTRA_FLAGS)
IOS_FRAMEWORKS += $(EXTRA_LIBS)

# Custom step to copy cacert.pem from libcurl build into the app bundle
check-cacert:
	@if [ ! -f "$(CURL_DIR)/lib/cacert.pem" ]; then \
		echo " [!] ERROR: cacert.pem missing in $(CURL_DIR)/lib/"; \
		echo "     Please rebuild libcurl to download it."; \
		exit 1; \
	fi

# Override the IPA target to inject our copy step
$(PHONE_IPA): $(APP_BUNDLE)
	@echo "  > copying cacert.pem into bundle"
	@cp $(CURL_DIR)/lib/cacert.pem $(APP_BUNDLE)/cacert.pem
	@echo " [4/4] Packaging IPA..."
	@rm -rf $(INT_DIR)/Payload
	@mkdir -p $(INT_DIR)/Payload
	@cp -R $(APP_BUNDLE) $(INT_DIR)/Payload/
	@cd $(INT_DIR) && zip -rq ../../$@ Payload
	@rm -rf $(INT_DIR)/Payload

release: check-cacert
debug: check-cacert
