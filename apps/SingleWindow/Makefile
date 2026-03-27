# Altivec Intelligence - SingleWindow (Mac)
APP_NAME = SingleWindow
RES_DIR = Resources
INFO_PLIST = Info.plist
SOURCES = main.m AppDelegate.m DownloadWindowController.m

# Include AICURLConnection
AIC_DIR = ../../libs/libcurl/build-mac
MAC_FLAGS = -I$(AIC_DIR)/include
MAC_LIBS = -L$(AIC_DIR)/lib -lAICURLConnection -lcurl -lssl -lcrypto -lz -lpthread -ldl

# Import common Mac build engine
include ../../altivec_common_mac.mk
