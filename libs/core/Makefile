# AltivecIntelligence AltivecCore Master Makefile
# Builds phone static archives and Mac static/framework artifacts.

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

# --- Combined/Alias Targets ---
mac-all:
	@echo "==========================================================="
	@echo "BUILDING MAC STATIC LIBS + ALTIVECCORE.framework"
	@echo "==========================================================="
	$(MAKE) -f Makefile-mac all

phone-all:
	@echo "==========================================================="
	@echo "BUILDING PHONE ALTIVECCORE STATIC LIBRARIES (armv7, arm64)"
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

.PHONY: all phone-static mac-static mac-dynamic mac-all phone-all phone mac clean prune-intermediates
