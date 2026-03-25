# AltivecIntelligence libcurl Master Makefile
# This Makefile orchestrates the build for iPhone and Mac

all: iphone mac

iphone:
	@echo "==========================================================="
	@echo "BUILDING IPHONE SLICES (armv7, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-phone

mac:
	@echo "==========================================================="
	@echo "BUILDING MAC SLICES (ppc, x86, x64, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-mac

clean:
	$(MAKE) -f Makefile-phone clean
	$(MAKE) -f Makefile-mac clean

.PHONY: all iphone mac clean
