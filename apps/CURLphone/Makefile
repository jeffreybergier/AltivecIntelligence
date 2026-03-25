# Altivec Intelligence - CURLphone (iPhone)
APP_NAME = CURLphone
SOURCES = main.m AppDelegate.m
INFO_PLIST = Info.plist

CURL_DIR = ../../libs/libcurl/build-phone
EXTRA_FLAGS = -I$(CURL_DIR)/include
EXTRA_LIBS = -L$(CURL_DIR)/lib -lcurl -lssl -lcrypto -lz -lresolv

# Import common iPhone build engine
include ../../altivec_common_phone.mk

# Override/Append
IOS_FLAGS += $(EXTRA_FLAGS)
IOS_FRAMEWORKS += $(EXTRA_LIBS)
