# Altivec Intelligence - CURLmac (Mac)
APP_NAME = CURLmac
SOURCES = main.m DownloadWindowController.m
INFO_PLIST = Info.plist

CURL_DIR = ../../libs/libcurl/build-mac
EXTRA_FLAGS = -I$(CURL_DIR)/include
LIBS_MAC = $(CURL_DIR)/lib/libAICURLConnection.a $(CURL_DIR)/lib/libcurl.a $(CURL_DIR)/lib/libssl.a $(CURL_DIR)/lib/libcrypto.a $(CURL_DIR)/lib/libz.a
EXTRA_LIBS = $(LIBS_MAC) -lpthread -ldl -framework SystemConfiguration

# Import common Mac build engine
include ../../altivec_common_mac.mk

# Override/Append
MAC_FLAGS += $(EXTRA_FLAGS)
MAC_LIBS += $(EXTRA_LIBS)

# Custom step to copy cacert.pem from libcurl build into the app bundle
EXTRA_BUNDLE_STEPS = \
	@echo "  > copying cacert.pem into bundle" ; \
	mkdir -p $(BUNDLE)/Contents/Resources ; \
	cp $(CURL_DIR)/lib/cacert.pem $(BUNDLE)/Contents/Resources/

check-cacert:
	@if [ ! -f "$(CURL_DIR)/lib/cacert.pem" ]; then \
		echo " [!] ERROR: cacert.pem missing in $(CURL_DIR)/lib/"; \
		echo "     Please rebuild libcurl to download it."; \
		exit 1; \
	fi

release: check-cacert
debug: check-cacert
