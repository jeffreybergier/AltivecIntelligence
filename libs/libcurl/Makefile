# AltivecIntelligence libcurl Master Makefile
# This Makefile orchestrates the build for Phone and Mac

all: phone-static mac-static

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

# --- Aliases ---
phone: phone-static
mac: mac-static

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
	       build-phone/intermediate \
	       build-mac/prefix/ppc \
	       build-mac/prefix/x86 \
	       build-mac/prefix/x64 \
	       build-mac/prefix/arm64 \
	       build-phone/prefix/armv7 \
	       build-phone/prefix/arm64

.PHONY: all phone-static mac-static phone mac aicc aicc-mac aicc-phone aicc-analyze clean prune-intermediates
