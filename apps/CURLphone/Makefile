# Altivec Intelligence - CURLphone (iPhone)
APP_NAME = CURLphone
SOURCES = main.m DownloadViewController.m KeyValueTableViewController.m CrossPlatform.m
INFO_PLIST = Info.plist

CURL_DIR = ../../libs/libcurl/build-phone
EXTRA_FLAGS = -I$(CURL_DIR)/include
LIBS_IPHONE = $(CURL_DIR)/lib/libAICURLConnection.a $(CURL_DIR)/lib/libcurl.a $(CURL_DIR)/lib/libssl.a $(CURL_DIR)/lib/libcrypto.a $(CURL_DIR)/lib/libz.a

# Resource files
RESOURCES = $(wildcard Resources/*.png)

include ../../altivec_common_phone.mk
