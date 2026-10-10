# Public product API. See docs/make-products.md.
ALTIVEC_ROOT ?= $(_altivec_entry)
include $(ALTIVEC_ROOT)/altivec_toolchains.mk
include $(ALTIVEC_ROOT)/make/config.mk
include $(ALTIVEC_ROOT)/make/dependencies.mk
include $(ALTIVEC_ROOT)/make/libraries.mk
include $(ALTIVEC_ROOT)/make/generated.mk
include $(ALTIVEC_ROOT)/make/compile.mk
include $(ALTIVEC_ROOT)/make/merge.mk
include $(ALTIVEC_ROOT)/make/resources.mk
include $(ALTIVEC_ROOT)/make/sign.mk
include $(ALTIVEC_ROOT)/make/package.mk
include $(ALTIVEC_ROOT)/make/targets.mk
.DEFAULT_GOAL := release

.DELETE_ON_ERROR:
