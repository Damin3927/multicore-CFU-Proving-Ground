TEST_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
TEST_BUILD := $(TEST_DIR)/build
CFUPG_ROOT := $(realpath $(TEST_DIR)/../..)

export
c_srcs += $(TEST_DIR)/fft.c
c_srcs += $(CFUPG_ROOT)/app/*.c

include ../base.mk
include $(CFUPG_ROOT)/config.mk

$(info c_srcs: $(c_srcs))

.PHONY: build
build:
	$(MAKE) -C $(CFUPG_ROOT) prog
	$(MAKE) -C $(CFUPG_ROOT) build

.PHONY: clean
clean:
	rm -rf $(TEST_BUILD)
	$(MAKE) -C $(CFUPG_ROOT) clean
