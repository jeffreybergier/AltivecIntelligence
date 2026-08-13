# Required project identity and source files.
APP_NAME := @ALTIVEC_APP_NAME@

SOURCES := \
	main.m \
	AppDelegate.m \
	UI/MainViewController.m \
	../shared/app_model.c

INCLUDE_DIRS := ../shared

# iPhone-only presentation assets live beside the UIKit target.
RESOURCES := \
	AppIcon29x29.png \
	AppIcon29x29@2x.png \
	AppIcon40x40@2x.png \
	AppIcon57x57.png \
	AppIcon57x57@2x.png \
	AppIcon60x60@2x.png \
	AppIcon60x60@3x.png \
	Default.png \
	Default@2x.png \
	Default-568h@2x.png \
	Default-iOS8-667h@2x.png \
	Default-iOS8-736h@3x.png \
	Default-iOS11-812h@3x.png \
	Default-iOS12-896h@2x.png \
	Default-iOS12-896h@3x.png

# Preserve the shared .lproj directories at the root of the application
# bundle. APP_PROJECT_ROOT bounds these sibling resource inputs to this repo.
APP_PROJECT_ROOT := ../..
BUNDLE_LOCALIZATION_DIRS := ../shared/Resources

IPHONEOS_DEPLOYMENT_TARGET := 5.0
APP_CFLAGS := -std=c99 -Wall -Wextra -Wpedantic -Werror
APP_OBJCFLAGS := -Wobjc-method-access -Wundeclared-selector
APP_USE_ARC := 1

ALTIVEC_PREFIX ?= /var/altivec
include $(ALTIVEC_PREFIX)/share/altivec/make/ios-app.mk
