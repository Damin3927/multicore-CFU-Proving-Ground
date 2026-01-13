GCC     := /tools/cad/riscv/rv32ima/bin/riscv32-unknown-elf-gcc
GPP     := /tools/cad/riscv/rv32ima/bin/riscv32-unknown-elf-g++
OBJCOPY := /tools/cad/riscv/rv32ima/bin/riscv32-unknown-elf-objcopy
OBJDUMP := /tools/cad/riscv/rv32ima/bin/riscv32-unknown-elf-objdump
VIVADO  := /tools/Xilinx/Vivado/2024.1/bin/vivado
VPP     := /tools/Xilinx/Vitis/2024.1/bin/v++
RTLSIM  := /tools/cad/bin/verilator

USE_HLS ?= 0
NCORES ?= 4
IMEM_SIZE_KB ?= 128
DMEM_SIZE_KB ?= 120
STACK_SIZE_KB ?= 2
CLK_FREQ_MHZ ?= 135

IMEM_SIZE ?= $(shell echo $(IMEM_SIZE_KB)*1024 | bc)
DMEM_SIZE ?= $(shell echo $(DMEM_SIZE_KB)*1024 | bc)
STACK_SIZE ?= $(shell echo $(STACK_SIZE_KB)*1024 | bc)
IMEM_SIZE_HEX := $(shell printf "0x%X" $(IMEM_SIZE))
DMEM_SIZE_HEX := $(shell printf "0x%X" $(DMEM_SIZE))
STACK_SIZE_HEX := $(shell printf "0x%X" $(STACK_SIZE))

src_dir := src
cfu_dir := cfu

verilog_srcs += $(wildcard *.v)
verilog_srcs += $(wildcard *.vh)
verilog_srcs += $(wildcard $(src_dir)/*.v)
verilog_srcs += $(wildcard $(src_dir)/cpu/*.v)
verilog_srcs += $(wildcard $(src_dir)/dmem/*.v)
verilog_srcs += $(wildcard $(src_dir)/imem/*.v)
verilog_srcs += $(wildcard $(src_dir)/vmem/*.v)
verilog_srcs += $(wildcard $(cfu_dir)/*.v)

ifndef c_srcs
c_srcs += app/*.c
c_srcs += *.c
endif

ifndef c_includes
c_includes += -Iapp
endif
