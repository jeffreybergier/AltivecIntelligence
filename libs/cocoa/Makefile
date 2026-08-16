# AltivecIntelligence AltivecCocoa Master Makefile
# Builds AltivecCocoa as a phone static library and Mac static/framework artifacts.

include ../../altivec_toolchains.mk

all: mac-all phone-all
all mac-static mac-dynamic mac-all mac phone-static phone-all phone: | altivec-sdk-install

mac-static:
	@echo "==========================================================="
	@echo "BUILDING MAC ALTIVECCOCOA STATIC LIBRARY (ppc, x86, x64, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-mac static

mac-dynamic:
	@echo "==========================================================="
	@echo "BUILDING MAC ALTIVECCOCOA.framework (ppc, x86, x64, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-mac dynamic

mac-all:
	@echo "==========================================================="
	@echo "BUILDING MAC STATIC LIB + ALTIVECCOCOA.framework"
	@echo "==========================================================="
	$(MAKE) -f Makefile-mac all

mac: mac-all

phone-static:
	@echo "==========================================================="
	@echo "BUILDING PHONE ALTIVECCOCOA STATIC LIBRARY (armv7, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-phone static

phone-all:
	@echo "==========================================================="
	@echo "BUILDING PHONE ALTIVECCOCOA STATIC LIBRARY (armv7, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-phone all

phone: phone-all

fontawesome-fetch:
	$(MAKE) -f Makefile-mac fontawesome-fetch

fontawesome-icons:
	$(MAKE) -f Makefile-mac fontawesome-icons

clean:
	$(MAKE) -f Makefile-mac clean
	$(MAKE) -f Makefile-phone clean

prune-intermediates:
	@echo "Pruning AltivecCocoa intermediates while keeping final outputs..."
	rm -rf build-mac/intermediate build-mac/stamps build-mac/prefix \
	       build-phone/intermediate build-phone/stamps build-phone/prefix

.PHONY: all mac-static mac-dynamic mac-all mac phone-static \
        phone-all phone fontawesome-fetch fontawesome-icons clean \
        prune-intermediates
