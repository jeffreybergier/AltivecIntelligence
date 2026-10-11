# Include before project declarations; make -f behaves exactly like make -C.
ifneq ($(words $(CURDIR)),1)
$(error Project paths must not contain whitespace; GNU Make paths are whitespace-delimited)
endif
_altivec_entry_file := $(abspath $(firstword $(MAKEFILE_LIST)))
_altivec_entry_dir := $(patsubst %/,%,$(dir $(_altivec_entry_file)))
ifneq ($(words $(_altivec_entry_file)),1)
$(error Makefile path must not contain whitespace)
endif
ifneq ($(CURDIR),$(_altivec_entry_dir))
_altivec_relocated := 1
.DEFAULT_GOAL := release
_altivec_goals := $(or $(MAKECMDGOALS),release)
.PHONY: $(_altivec_goals) _altivec_forward
$(_altivec_goals): _altivec_forward ;
_altivec_forward:
	+$(MAKE) --no-print-directory -C "$(_altivec_entry_dir)" -f "$(notdir $(_altivec_entry_file))" $(_altivec_goals)
endif
