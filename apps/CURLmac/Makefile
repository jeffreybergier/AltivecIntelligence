# Altivec Intelligence - CURLmac (Mac)
APP_NAME = CURLmac
SOURCES = main.m AppDelegate.m
INFO_PLIST = Info.plist

CURL_DIR = ../../libs/libcurl/build-mac
EXTRA_FLAGS = -I$(CURL_DIR)/include
LIBS_MAC = $(CURL_DIR)/lib/libAICURLConnection.a $(CURL_DIR)/lib/libcurl.a $(CURL_DIR)/lib/libssl.a $(CURL_DIR)/lib/libcrypto.a $(CURL_DIR)/lib/libz.a
EXTRA_LIBS = $(LIBS_MAC) -lpthread -ldl -framework SystemConfiguration -lldap -llber

# Import common Mac build engine
include ../../altivec_common_mac.mk

# Override/Append
MAC_FLAGS += $(EXTRA_FLAGS)
MAC_LIBS += $(EXTRA_LIBS)
