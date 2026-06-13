# AltivecIntelligence AltivecCocoa Master Makefile
# Builds AltivecCocoa as a phone static library and Mac static/framework artifacts.

all: mac-all phone-all

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

clean:
	$(MAKE) -f Makefile-mac clean
	$(MAKE) -f Makefile-phone clean

prune-intermediates:
	@echo "Pruning AltivecCocoa intermediates while keeping final outputs..."
	rm -rf build-mac/intermediate build-mac/stamps build-mac/prefix \
	       build-phone/intermediate build-phone/stamps build-phone/prefix

.PHONY: all mac-static mac-dynamic mac-all mac phone-static \
        phone-all phone clean prune-intermediates
