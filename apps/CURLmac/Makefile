# Altivec Intelligence - CURLmac (Mac)
APP_NAME = CURLmac
SOURCES = main.m DownloadWindowController.m
INFO_PLIST = Info.plist

LIBCURL_REQUIRED = 1

# Import common Mac build engine
include ../../altivec_common_mac.mk

# Custom step to copy cacert.pem from libcurl build into the app bundle
EXTRA_BUNDLE_STEPS = \
	@echo "  > copying cacert.pem into bundle" ; \
	mkdir -p $(BUNDLE)/Contents/Resources ; \
	cp $(LIBCURL_DIR)/lib/cacert.pem $(BUNDLE)/Contents/Resources/
