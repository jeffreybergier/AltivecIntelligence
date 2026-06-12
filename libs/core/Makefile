# AltivecIntelligence AltivecCore Master Makefile
# Builds static archives plus AltivecCore.framework for Phone and Mac.

all: phone-all mac-all

# --- Static Targets ---
phone-static:
	@echo "==========================================================="
	@echo "BUILDING PHONE ALTIVECCORE STATIC LIBRARIES (armv7, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-phone static

mac-static:
	@echo "==========================================================="
	@echo "BUILDING MAC ALTIVECCORE STATIC LIBRARIES (ppc, x86, x64, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-mac static

# --- Dynamic Targets ---
mac-dynamic:
	@echo "==========================================================="
	@echo "BUILDING MAC ALTIVECCORE.framework (ppc, x86, x64, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-mac dynamic

phone-dynamic:
	@echo "==========================================================="
	@echo "BUILDING PHONE ALTIVECCORE.framework (armv7, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-phone dynamic

# --- Combined: Static Libraries + AltivecCore.framework ---
mac-all:
	@echo "==========================================================="
	@echo "BUILDING MAC STATIC LIBS + ALTIVECCORE.framework"
	@echo "==========================================================="
	$(MAKE) -f Makefile-mac all

phone-all:
	@echo "==========================================================="
	@echo "BUILDING PHONE STATIC LIBS + ALTIVECCORE.framework"
	@echo "==========================================================="
	$(MAKE) -f Makefile-phone all

# --- Aliases ---
phone: phone-all
mac: mac-all

clean:
	$(MAKE) -f Makefile-phone clean
	$(MAKE) -f Makefile-mac clean

prune-intermediates:
	@echo "Pruning AltivecCore intermediates while keeping final outputs..."
	rm -rf build-mac/intermediate \
	       build-mac/stamps \
	       build-phone/intermediate \
	       build-phone/stamps

.PHONY: all phone-static mac-static mac-dynamic phone-dynamic mac-all phone-all phone mac clean prune-intermediates
