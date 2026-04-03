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

.PHONY: all phone-static mac-static phone mac aicc aicc-mac aicc-phone aicc-analyze clean
