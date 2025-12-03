COREMARK_PRO_DIR := tests/coremark-pro
COREMARK_PRO_SRC := $(COREMARK_PRO_DIR)/coremark-pro-src
COREMARK_PRO_BUILD := $(COREMARK_PRO_SRC)/builds/cfupg/riscv32-cfupg

WORKLOAD := core
XCMD ?= -c$(NCORES)

.PHONY: coremark-pro-prog
coremark-pro-prog:
	$(MAKE) -C $(COREMARK_PRO_SRC) \
		-I$(PWD)/$(COREMARK_PRO_SRC)/util/make \
		-I$(PWD)/$(COREMARK_PRO_DIR) \
		TARGET=cfupg \
		TOOLCHAIN=riscv32-cfupg \
		CFUPG_ROOT=$(PWD) \
		CFUPG_AL_DIR=$(PWD)/$(COREMARK_PRO_DIR)/al \
		NCORES=$(NCORES) \
		XCMD="$(XCMD)" \
		wbuild-$(WORKLOAD)
	cp $(COREMARK_PRO_BUILD)/bin/core.elf build/main.elf
	$(MAKE) initf

.PHONY: coremark-pro
coremark-pro: coremark-pro-prog build

.PHONY: coremark-pro-clean
coremark-pro-clean:
	$(MAKE) -C $(COREMARK_PRO_SRC) \
		-I$(PWD)/$(COREMARK_PRO_SRC)/util/make \
		-I$(PWD)/$(COREMARK_PRO_DIR) \
		TARGET=cfupg \
		TOOLCHAIN=riscv32-cfupg \
		distclean
	rm -f $(COREMARK_PRO_DIR)/al/src/*.o
	rm -f app/*.o
