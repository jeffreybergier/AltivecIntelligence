# AltivecIntelligence libcurl Master Makefile
# This Makefile orchestrates the build for Phone and Mac

all: phone-all mac-all

# --- Static Targets ---
phone-static:
	@echo "==========================================================="
	@echo "BUILDING PHONE STATIC LIBRARIES (armv7, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-phone static

mac-static:
	@echo "==========================================================="
	@echo "BUILDING MAC STATIC LIBRARIES (ppc, x86, x64, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-mac static

# --- Dynamic Targets ---
mac-dynamic:
	@echo "==========================================================="
	@echo "BUILDING MAC ALTIVECCURL.framework (ppc, x86, x64, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-mac dynamic

phone-dynamic:
	@echo "==========================================================="
	@echo "BUILDING PHONE ALTIVECCURL.framework (armv7, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-phone dynamic

# --- Combined: Static Libraries + AltivecCURL.framework ---
mac-all:
	@echo "==========================================================="
	@echo "BUILDING MAC STATIC LIBS + ALTIVECCURL.framework"
	@echo "==========================================================="
	$(MAKE) -f Makefile-mac all

phone-all:
	@echo "==========================================================="
	@echo "BUILDING PHONE STATIC LIBS + ALTIVECCURL.framework"
	@echo "==========================================================="
	$(MAKE) -f Makefile-phone all

# --- Aliases ---
phone: phone-all
mac: mac-all

# --- AICURLConnection Only Targets ---
aicc: aicc-mac

aicc-mac:
	@echo "==========================================================="
	@echo "BUILDING MAC AICURLConnection (ppc, x86, x64, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-mac aicc

aicc-phone:
	@echo "==========================================================="
	@echo "BUILDING PHONE AICURLConnection (armv7, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-phone aicc

aicc-analyze:
	@echo "==========================================================="
	@echo "ANALYZING AICURLConnection (x64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-mac aicc-analyze

clean:
	$(MAKE) -f Makefile-phone clean
	$(MAKE) -f Makefile-mac clean

prune-intermediates:
	@echo "Pruning libcurl intermediates while keeping final outputs..."
	rm -rf build-mac/intermediate \
	       build-mac/stamps \
	       build-mac/prefix \
	       build-phone/intermediate \
	       build-phone/stamps \
	       build-phone/prefix

.PHONY: all phone-static mac-static mac-dynamic phone-dynamic mac-all phone-all phone mac aicc aicc-mac aicc-phone aicc-analyze clean prune-intermediates
