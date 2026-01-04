# CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo
# Released under the MIT license https://opensource.org/licenses/mit

include config.mk

#TARGET := arty_a7
#TARGET := cmod_a7
TARGET := nexys_a7

.PHONY: build prog run clean
all: prog build

build:
	$(RTLSIM) --binary --trace --top-module top -DNCORES=$(NCORES) -DIMEM_SIZE=$(IMEM_SIZE) -DDMEM_SIZE=$(DMEM_SIZE) -DSTACK_SIZE=$(STACK_SIZE) $(if $(filter 1,$(USE_HLS)),-DUSE_HLS --Wno-TIMESCALEMOD) --Wno-WIDTHTRUNC --Wno-WIDTHEXPAND -o top $(verilog_srcs)
	gcc -O2 dispemu/dispemu.c -o build/dispemu -lcairo -lX11

prog:
	mkdir -p build
	$(GCC) -Os -march=rv32ima -mabi=ilp32 -nostartfiles -ffunction-sections -fdata-sections -Wl,--gc-sections \
		$(c_includes) -Tapp/link.ld \
		-Wl,--defsym,_num_cores=$(NCORES) \
		-Wl,--defsym,IMEM_SIZE=$(IMEM_SIZE_HEX) \
		-Wl,--defsym,DMEM_SIZE=$(DMEM_SIZE_HEX) \
		-Wl,--defsym,_stack_size=$(STACK_SIZE_HEX) \
		-DNCORES=$(NCORES) $(if $(filter 1,$(USE_HLS)),-DUSE_HLS) -o build/main.elf app/crt0.s $(c_srcs) -lm
	make initf

initf:
	$(OBJDUMP) -D build/main.elf > build/main.dump
	$(OBJCOPY) -O binary --only-section=.text build/main.elf build/memi.bin.tmp; \
	$(OBJCOPY) -O binary --only-section=.data \
						 --only-section=.rodata \
						 --only-section=.bss \
						 build/main.elf build/memd.bin.tmp; \
	for suf in i d; do \
		if [ "$$suf" = "i" ]; then \
			mem_size=$(IMEM_SIZE); \
		else \
			mem_size=$(DMEM_SIZE); \
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
	$(VIVADO) -mode batch -source build.tcl -tclargs --ncores $(NCORES) --imem_size $(IMEM_SIZE) --dmem_size $(DMEM_SIZE) --stack_size $(STACK_SIZE) $(if $(filter 1,$(USE_HLS)),--hls)
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
	rm -rf obj_dir rvcpu-32im* vivado* .Xil $(cfu_dir) app/*.o

reset-hard: clean
	rm -rf build build.tcl main.xdc
