COREMARK_PRO_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
COREMARK_PRO_SRC := $(COREMARK_PRO_DIR)/coremark-pro-src
COREMARK_PRO_BUILD := $(COREMARK_PRO_SRC)/builds/cfupg/riscv32-cfupg
CFUPG_ROOT := $(realpath $(COREMARK_PRO_DIR)/../..)

include ../base.mk
include $(CFUPG_ROOT)/config.mk

WORKLOAD := core
XCMD ?= -c$(NCORES)

.PHONY: prog
prog:
	$(MAKE) -C $(COREMARK_PRO_SRC) \
		-I$(COREMARK_PRO_SRC)/util/make \
		-I$(COREMARK_PRO_DIR) \
		TARGET=cfupg \
		TOOLCHAIN=riscv32-cfupg \
		CFUPG_ROOT=$(CFUPG_ROOT) \
		CFUPG_AL_DIR=$(COREMARK_PRO_DIR)/al \
		NCORES=$(NCORES) \
		XCMD="$(XCMD)" \
		wbuild-$(WORKLOAD)
	mkdir -p $(CFUPG_ROOT)/build
	cp $(COREMARK_PRO_BUILD)/bin/core.elf $(CFUPG_ROOT)/build/main.elf
	$(MAKE) -C $(CFUPG_ROOT) initf

.PHONY: build
build:
	$(MAKE) prog
	$(MAKE) -C $(CFUPG_ROOT) build

.PHONY: clean
clean:
	$(MAKE) -C $(CFUPG_ROOT) clean
	$(MAKE) -C $(COREMARK_PRO_SRC) \
		-I$(PWD)/$(COREMARK_PRO_SRC)/util/make \
		-I$(PWD)/$(COREMARK_PRO_DIR) \
		TARGET=cfupg \
		TOOLCHAIN=riscv32-cfupg \
		distclean
	rm -f $(COREMARK_PRO_DIR)/al/src/*.o
