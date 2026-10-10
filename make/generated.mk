# A shared output has one command stamp across debug/release submakes.
generator_stamp = $(BUILD_ROOT)/generators/$(patsubst /%,%,$(abspath $(GEN_$(1)_OUTPUT))).command
define generator_rule
$(GEN_$(1)_OUTPUT): $(GEN_$(1)_INPUTS) $(call generator_stamp,$(1))
	@mkdir -p "$$(dir $$@)"
	$(ALTIVEC_BUILD_TOOL) generate $(call q,$(GEN_$(1)_OUTPUT)) $(call q,$(GEN_$(1)_COMMAND)) $(foreach f,$(GEN_$(1)_INPUTS) $(call generator_stamp,$(1)),$(call q,$(f)))
$(call generator_stamp,$(1)): FORCE
	@$(ALTIVEC_BUILD_TOOL) stamp "$$@" $(call q,$(GEN_$(1)_COMMAND) $(GEN_$(1)_INPUTS))
endef
$(foreach g,$(GENERATORS),$(eval $(call generator_rule,$(g))))
