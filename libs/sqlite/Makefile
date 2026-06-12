# AltivecIntelligence SQLite Master Makefile
# Builds SQLite as a static library for Mac (quad-fat) and Phone (universal)

all: phone mac

phone:
	@echo "==========================================================="
	@echo "BUILDING PHONE STATIC LIBRARY (armv7, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-phone static

mac:
	@echo "==========================================================="
	@echo "BUILDING MAC STATIC LIBRARY (ppc, x86, x64, arm64)"
	@echo "==========================================================="
	$(MAKE) -f Makefile-mac static

clean:
	$(MAKE) -f Makefile-phone clean
	$(MAKE) -f Makefile-mac clean

.PHONY: all phone mac clean
