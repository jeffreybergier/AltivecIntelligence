SHELL := /bin/bash

.DEFAULT_GOAL := release

IOS_TARGET_DIR := source/iOS

.PHONY: release analyze clean

release analyze clean:
	+$(MAKE) --no-print-directory -C "$(IOS_TARGET_DIR)" $@
