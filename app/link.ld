/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

OUTPUT_ARCH("riscv")
ENTRY(_start)

_stack_size_per_core = 2K;
/* _num_cores is defined via -Wl,--defsym,_num_cores=N from Makefile */
_total_stack_size = _stack_size_per_core * _num_cores;

MEMORY {
    imem : ORIGIN = 0x00000000, LENGTH = 0x00020000
    dmem : ORIGIN = 0x10000000, LENGTH = 0x00020000
}

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text.*)
        *(.text)
    } > imem

    .data : {
        *(.data.*)
        *(.sdata*)
        *(.data)
    } > dmem

    .rodata : {
        *(.rodata.*)
        *(.srodata.*)
        *(.rodata)
    } > dmem

    .bss : {
        *(.bss.*)
        *(.sbss)
        *(.bss)
        *(COMMON)
        _end = .;
    } > dmem

    .heap : {
        . = ALIGN(16);
        _heap_start = .;
        . = ORIGIN(dmem) + LENGTH(dmem) - _total_stack_size;
        _heap_end = .;
    } > dmem

    /DISCARD/ : {
        *(.debug*)
    }
}

PROVIDE(_tohost = 0x80000000);
PROVIDE(_fstack = ORIGIN(dmem) + LENGTH(dmem));
PROVIDE(__heap_start = _heap_start);
PROVIDE(__heap_end = _heap_end);
