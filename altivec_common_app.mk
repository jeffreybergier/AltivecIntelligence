# Shared app build helpers for altivec_common_mac.mk and
# altivec_common_phone.mk.

# Additional source lookup directories for both pattern rules and analysis.
# Local app files are always searched from ".".
SOURCE_DIRS ?=
ifneq ($(strip $(SOURCE_DIRS)),)
vpath %.m $(SOURCE_DIRS)
vpath %.c $(SOURCE_DIRS)
endif

# --- Object and Source Mapping ---
ALL_SOURCES = $(SOURCES) $(EXTRA_SOURCES)
app_objs = $(addprefix $(1)/, \
  $(filter %.o,$(2:.m=.o) $(2:.c=.o)))
APP_SOURCE_OBJS = $(call app_objs,$(INT_DIR),$(SOURCES))
APP_EXTRA_OBJS = $(call app_objs,$(INT_DIR),$(EXTRA_SOURCES))
APP_OBJS = $(APP_SOURCE_OBJS) $(APP_EXTRA_OBJS)

# --- Static Analyzer ---
# SOURCE_DIRS is the normal way to teach both make pattern rules and the
# analyzer about shared source roots. ANALYZE_DIRS remains available when the
# analyzer needs a different search path from the compiler.
ANALYZE_DIRS       ?= . $(SOURCE_DIRS)
ANALYZE_OUTPUT_DIR ?= build-analyze
ANALYZE_OUTPUT     ?= $(ANALYZE_OUTPUT_DIR)/analyze.txt
analyze_find        = $(firstword $(wildcard $(1)) \
                       $(foreach d,$(ANALYZE_DIRS),$(wildcard $(d)/$(1))))
analyze_missing     = $(if $(call analyze_find,$(1)),,$(1))
ANALYZE_SOURCE_FILES = $(foreach s,$(SOURCES),$(call analyze_find,$(s)))
ANALYZE_EXTRA_SOURCE_FILES = $(foreach s,$(EXTRA_SOURCES), \
                              $(call analyze_find,$(s)))
ANALYZE_SOURCES = $(ANALYZE_SOURCE_FILES) $(ANALYZE_EXTRA_SOURCE_FILES)
ANALYZE_MISSING_SOURCES = $(foreach s,$(ALL_SOURCES), \
                            $(call analyze_missing,$(s)))

define analyze_check_sources
	@if [ -n "$(strip $(ANALYZE_MISSING_SOURCES))" ]; then \
		echo " [!] ERROR: Static analyzer could not resolve: $(ANALYZE_MISSING_SOURCES)"; \
		echo "     Add source roots with SOURCE_DIRS or ANALYZE_DIRS."; \
		exit 1; \
	fi
endef

define analyze_report
	@warnings=$$(grep -cE '^.+:[0-9]+:[0-9]+: warning:' $(ANALYZE_OUTPUT) 2>/dev/null || true); \
	errors=$$(grep -cE '^.+:[0-9]+:[0-9]+: error:' $(ANALYZE_OUTPUT) 2>/dev/null || true); \
	echo "  > $${warnings:-0} warning(s), $${errors:-0} error(s) - see $(ANALYZE_OUTPUT)"
endef

# Directories the local Makefile wants validated before a build/analyze runs.
# Dep dirs may be omitted when their own build systems manage bootstrapping.
VALIDATE_PATHS ?=

validate-paths:
	@for dir in $(VALIDATE_PATHS); do \
		if [ ! -d "$$dir" ]; then \
			echo " [!] ERROR: Project directory missing: $$dir"; \
			exit 1; \
		fi; \
	done

# --- Bundle Resource Helpers ---
define copy_bundle_resources
	@if [ -d "$(RES_DIR)" ]; then \
		did_copy=0 ; \
		for res in "$(RES_DIR)"/*; do \
			[ -e "$$res" ] || continue ; \
			[ "$$(basename "$$res")" = "Info.plist" ] && continue ; \
			if [ "$$did_copy" = "0" ]; then echo "  > copying resources" ; did_copy=1 ; fi ; \
			cp -R "$$res" $(1)/ ; \
		done ; \
	fi
endef

define copy_bundle_fonts
	@for dir in $(BUNDLE_FONT_DIRS); do \
		if [ -d "$$dir" ] && [ "$$(ls -A "$$dir" 2>/dev/null)" ]; then \
			echo "  > copying fonts from $$dir" ; \
			mkdir -p $(1) ; \
			cp -R "$$dir"/* $(1)/ ; \
		fi ; \
	done
endef

define copy_bundle_localizations
	@for dir in $(BUNDLE_LOCALIZATION_DIRS); do \
		if ls "$$dir"/*.lproj >/dev/null 2>&1; then \
			echo "  > copying localizations from $$dir" ; \
			for lproj in "$$dir"/*.lproj; do \
				[ -d "$$lproj" ] || continue ; \
				cp -R "$$lproj" $(1)/ ; \
				if [ "$(2)" = "utf16" ]; then \
					for strings in "$$lproj"/*.strings; do \
						[ -f "$$strings" ] || continue ; \
						dest="$(1)/$$(basename "$$lproj")/$$(basename "$$strings")" ; \
						tmp="$$dest.utf16" ; \
						echo "  > transcoding $$(basename "$$lproj")/$$(basename "$$strings") to UTF-16 LE" ; \
						printf '\377\376' > "$$tmp" ; \
						iconv -f UTF-8 -t UTF-16LE "$$strings" >> "$$tmp" ; \
						mv "$$tmp" "$$dest" ; \
					done ; \
				fi ; \
			done ; \
		fi ; \
	done
endef

define copy_altiveccocoa_fonts
	@if [ "$(1)" = "1" ] && [ "$(ALTIVECCOCOA_REQUIRED)" = "1" ] && [ -d "$(ALTIVECCOCOA_RESOURCE_DIR)/Fonts" ]; then \
		echo "  > copying AltivecCocoa fonts" ; \
		mkdir -p $(2) ; \
		cp "$(ALTIVECCOCOA_RESOURCE_DIR)"/Fonts/*.otf $(2)/ ; \
		cp "$(ALTIVECCOCOA_RESOURCE_DIR)"/Fonts/LICENSE-Font-Awesome.txt $(2)/ ; \
	fi
endef

# --- Altivec Library Bootstrap / Validation ---
altiveccore-bootstrap:
	@if [ "$(ALTIVECCORE_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(ALTIVECCORE_DIR)" ]; then \
		echo " [!] ERROR: AltivecCore is required but ALTIVECCORE_DIR is not set."; \
		echo "     Set ALTIVECCORE_DIR=/path/to/libs/core/$(ALTIVECCORE_BUILD_DIR) or build at $(ALTIVEC_ROOT)/libs/core/$(ALTIVECCORE_BUILD_DIR)."; \
		exit 1; \
	fi
	@probe="$(ALTIVECCORE_BOOTSTRAP_PROBE)"; \
	target="$(ALTIVECCORE_BOOTSTRAP_TARGET)"; \
	if [ ! -e "$$probe" ]; then \
		echo " [!] Missing AltivecCore artifact ($$probe), running bootstrap build ($$target)..."; \
		$(MAKE) -C $(ALTIVEC_ROOT)/libs/core $$target; \
	fi

libs-ready: altiveccore-bootstrap altiveccore-ready

altiveccore-ready:
	@if [ "$(ALTIVECCORE_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(ALTIVECCORE_DIR)" ]; then \
		echo " [!] ERROR: AltivecCore is required but ALTIVECCORE_DIR is not set."; \
		echo "     Set ALTIVECCORE_DIR=/path/to/libs/core/$(ALTIVECCORE_BUILD_DIR)."; \
		exit 1; \
	fi
	@missing=""; \
	for f in $(ALTIVECCORE_REQUIRED_FILES); do \
		if [ ! -f "$$f" ]; then missing="$$missing $$f"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo " [!] ERROR: Missing required AltivecCore artifacts:$$missing"; \
		echo "     Build them with: make -C $(ALTIVEC_ROOT)/libs/core $(ALTIVEC_PLATFORM_TARGET)"; \
		exit 1; \
	fi

altiveccocoa-bootstrap:
	@if [ "$(ALTIVECCOCOA_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(ALTIVECCOCOA_DIR)" ]; then \
		echo " [!] ERROR: AltivecCocoa is required but ALTIVECCOCOA_DIR is not set."; \
		echo "     Set ALTIVECCOCOA_DIR=/path/to/libs/cocoa/$(ALTIVECCOCOA_BUILD_DIR) or build at $(ALTIVEC_ROOT)/libs/cocoa/$(ALTIVECCOCOA_BUILD_DIR)."; \
		exit 1; \
	fi
	@probe="$(ALTIVECCOCOA_BOOTSTRAP_PROBE)"; \
	target="$(ALTIVECCOCOA_BOOTSTRAP_TARGET)"; \
	if [ ! -e "$$probe" ]; then \
		echo " [!] Missing AltivecCocoa artifact ($$probe), running bootstrap build ($$target)..."; \
		$(MAKE) -C $(ALTIVEC_ROOT)/libs/cocoa $$target; \
	fi

cocoa-ready: altiveccocoa-bootstrap altiveccocoa-ready

altiveccocoa-ready:
	@if [ "$(ALTIVECCOCOA_REQUIRED)" != "1" ]; then exit 0; fi
	@if [ -z "$(ALTIVECCOCOA_DIR)" ]; then \
		echo " [!] ERROR: AltivecCocoa is required but ALTIVECCOCOA_DIR is not set."; \
		echo "     Set ALTIVECCOCOA_DIR=/path/to/libs/cocoa/$(ALTIVECCOCOA_BUILD_DIR)."; \
		exit 1; \
	fi
	@missing=""; \
	for f in $(ALTIVECCOCOA_REQUIRED_FILES); do \
		if [ ! -f "$$f" ]; then missing="$$missing $$f"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo " [!] ERROR: Missing required AltivecCocoa artifacts:$$missing"; \
		echo "     Build them with: make -C $(ALTIVEC_ROOT)/libs/cocoa $(ALTIVEC_PLATFORM_TARGET)"; \
		exit 1; \
	fi

.PHONY: validate-paths altiveccore-bootstrap libs-ready altiveccore-ready \
        altiveccocoa-bootstrap cocoa-ready altiveccocoa-ready
