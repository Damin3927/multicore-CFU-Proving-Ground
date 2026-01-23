/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

OUTPUT_ARCH("riscv")
ENTRY(_start)

PROVIDE(_stack_size = 2K);
_stack_base = 0x18000000;
PROVIDE(IMEM_SIZE = 0x00020000);
PROVIDE(DMEM_SIZE = 0x00020000);

MEMORY {
    imem : ORIGIN = 0x00000000, LENGTH = IMEM_SIZE
    dmem : ORIGIN = 0x10000000, LENGTH = DMEM_SIZE
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
        . = ORIGIN(dmem) + LENGTH(dmem);
        _heap_end = .;
    } > dmem

    /DISCARD/ : {
        *(.debug*)
    }
}

PROVIDE(_tohost = 0x80000000);
PROVIDE(_fstack = _stack_base + _stack_size);
PROVIDE(__heap_start = _heap_start);
PROVIDE(__heap_end = _heap_end);
