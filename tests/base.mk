.DEFAULT_GOAL := build

.PHONY: run
run:
	$(MAKE) -C $(CFUPG_ROOT) run

.PHONY: drun
drun:
	$(MAKE) -C $(CFUPG_ROOT) drun
