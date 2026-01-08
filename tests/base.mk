.DEFAULT_GOAL := build

.PHONY: prog
prog:
	$(MAKE) -C $(CFUPG_ROOT) prog

.PHONY: run
run:
	$(MAKE) -C $(CFUPG_ROOT) run

.PHONY: drun
drun:
	$(MAKE) -C $(CFUPG_ROOT) drun

.PHONY: bit
bit:
	$(MAKE) -C $(CFUPG_ROOT) bit

.PHONY: vpp
vpp:
	$(MAKE) -C $(CFUPG_ROOT) vpp CFU_HLS_SRC=$(TEST_DIR)/cfu_hls.c
