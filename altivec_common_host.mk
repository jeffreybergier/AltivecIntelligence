# Native offline harnesses use the same dependency graph as cross-products.
ALTIVEC_PLATFORM := host
ARCHS ?= host
CC_host ?= $(shell command -v $(CC))
CXX_host ?= $(shell command -v $(CXX))
AR_host ?= $(shell command -v $(AR))
SDK_host ?= /
MIN_host ?= 0
_altivec_entry := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
include $(_altivec_entry)/make/products.mk
