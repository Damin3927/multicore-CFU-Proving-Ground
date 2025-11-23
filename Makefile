# CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo
# Released under the MIT license https://opensource.org/licenses/mit

GCC     := /tools/cad/riscv/rv32ima/bin/riscv32-unknown-elf-gcc
GPP     := /tools/cad/riscv/rv32ima/bin/riscv32-unknown-elf-g++
OBJCOPY := /tools/cad/riscv/rv32ima/bin/riscv32-unknown-elf-objcopy
OBJDUMP := /tools/cad/riscv/rv32ima/bin/riscv32-unknown-elf-objdump
VIVADO  := /tools/Xilinx/Vivado/2024.1/bin/vivado
VPP     := /tools/Xilinx/Vitis/2024.1/bin/v++
RTLSIM  := /tools/cad/bin/verilator

#TARGET := arty_a7
#TARGET := cmod_a7
TARGET := nexys_a7

USE_HLS ?= 0
NCORES ?= 4

.PHONY: build prog run clean
all: prog build

src_dir := src
cfu_dir := cfu
srcs += $(wildcard *.v)
srcs += $(wildcard *.vh)
srcs += $(wildcard $(src_dir)/*.v)
srcs += $(wildcard $(src_dir)/cpu/*.v)
srcs += $(wildcard $(src_dir)/dmem/*.v)
srcs += $(wildcard $(src_dir)/imem/*.v)
srcs += $(wildcard $(src_dir)/vmem/*.v)
srcs += $(wildcard $(cfu_dir)/*.v)

build:
	$(RTLSIM) --binary --trace --top-module top -DNCORES=$(NCORES) $(if $(filter 1,$(USE_HLS)),-DUSE_HLS --Wno-TIMESCALEMOD) --Wno-WIDTHTRUNC --Wno-WIDTHEXPAND -o top $(srcs)
	gcc -O2 dispemu/dispemu.c -o build/dispemu -lcairo -lX11

prog:
	mkdir -p build
	$(GCC) -Os -march=rv32ima -mabi=ilp32 -nostartfiles -Iapp -Tapp/link.ld -DNCORES=$(NCORES) $(if $(filter 1,$(USE_HLS)),-DUSE_HLS) -o build/main.elf app/crt0.s app/*.c *.c
	make initf

imem_size =	$(shell grep -oP "\`define\s+IMEM_SIZE\s+\(\K[^)]*" config.vh | bc)
dmem_size =	$(shell grep -oP "\`define\s+DMEM_SIZE\s+\(\K[^)]*" config.vh | bc)
initf:
	$(OBJDUMP) -D build/main.elf > build/main.dump
	$(OBJCOPY) -O binary --only-section=.text build/main.elf build/memi.bin.tmp; \
	$(OBJCOPY) -O binary --only-section=.data \
						 --only-section=.rodata \
						 --only-section=.bss \
						 build/main.elf build/memd.bin.tmp; \
	for suf in i d; do \
		if [ "$$suf" = "i" ]; then \
			mem_size=$(imem_size); \
		else \
			mem_size=$(dmem_size); \
		fi; \
		dd if=build/mem$$suf.bin.tmp of=build/mem$$suf.bin conv=sync bs=$$mem_size; \
		rm -f build/mem$$suf.bin.tmp; \
		hexdump -v -e '1/4 "%08x\n"' build/mem$$suf.bin > build/mem$$suf.32.hex; \
		tmp_IFS=$$IFS; IFS= ; \
		cnt=0; \
		{ \
			echo "initial begin"; \
			while read -r line; do \
				echo "    $${suf}mem[$$cnt] = 32'h$$line;"; \
				cnt=$$((cnt + 1)); \
			done < build/mem$$suf.32.hex; \
			echo "end"; \
		} > mem$$suf.txt; \
		IFS=$$tmp_IFS; \
	done

run:
	./obj_dir/top

drun:
	./obj_dir/top | build/dispemu 1

bit:
	@if [ ! -f memi.txt ] || [ ! -f memd.txt ]; then \
		echo "Please run 'make prog' first."; \
		exit 1; \
	fi
	@if [ ! -f build.tcl ]; then \
		echo "Plese run 'make init' first."; \
		exit 1; \
	fi
	$(VIVADO) -mode batch -source build.tcl -tclargs --ncores $(NCORES) $(if $(filter 1,$(USE_HLS)),--hls)
	cp vivado/main.runs/impl_1/main.bit build/.
	@if [ -f vivado/main.runs/impl_i/main.ltx ]; then \
		cp -f vivado/main.runs/impl_i/main.ltx build/.; \
	fi

conf:
	@if [ ! -f build/main.bit ]; then \
		echo "Please run 'make bit' first."; \
		exit 1; \
	fi
	$(VIVADO) -mode batch -source scripts/prog_dev.tcl

vpp:
	$(VPP) -c --mode hls --config constr/cfu_hls.cfg --work_dir vitis
	if [ -d $(cfu_dir) ]; then rm -rf $(cfu_dir); fi
	mkdir -p $(cfu_dir)
	cp vitis/hls/impl/verilog/*.v $(cfu_dir)/.
	cp vitis/hls/impl/verilog/*.tcl $(cfu_dir)/.

hls-sim:
	make prog USE_HLS=1
	make build USE_HLS=1

init:
	cp constr/$(TARGET).xdc main.xdc
	cp constr/build_$(TARGET).tcl build.tcl

clean:
	rm -rf obj_dir rvcpu-32im* vivado* .Xil $(cfu_dir)

reset-hard:
	rm -rf obj_dir build rvcpu-32im* sample1.txt vivado* .Xil build.tcl main.xdc $(cfu_dir)
