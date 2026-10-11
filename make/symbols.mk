# Keep modern slice symbols next to the product; legacy debug info stays embedded.
SYMBOLS ?= 1
symbol_archs = $(if $(filter 1,$(SYMBOLS)),$(filter-out host ppc i386,$(ARCHS)))
symbol = $(call product_dir,$(1))/$(1).$(2).dSYM/Contents/Resources/DWARF/$(1)
define symbol_rule
$(call symbol,$(1),$(2)): $(call slice,$(1),$(2))
	$(DSYMUTIL) "$$<" -o "$(call product_dir,$(1))/$(1).$(2).dSYM"
_package: $(call symbol,$(1),$(2))
_product-$(1): $(call symbol,$(1),$(2))
endef
$(foreach p,$(PRODUCTS),$(if $(filter static,$($(p)_TYPE)),,$(foreach a,$(call symbol_archs),$(eval $(call symbol_rule,$(p),$(a))))))
