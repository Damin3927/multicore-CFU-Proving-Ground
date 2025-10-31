# Testing RV32A LR/SC Instructions

## Overview
This document describes how to test the newly implemented LR (Load-Reserved) and SC (Store-Conditional) instructions from the RV32A atomic extension.

## Implementation Details

### Instruction Encoding
- **LR.W** (Load-Reserved Word):
  - Opcode: 0x2F (0101111)
  - funct3: 0x2 (010)
  - funct5: 0x2 (00010)
  - Format: `lr.w rd, (rs1)`
  - Effect: Loads word from address in rs1, sets reservation on that address

- **SC.W** (Store-Conditional Word):
  - Opcode: 0x2F (0101111)
  - funct3: 0x2 (010)
  - funct5: 0x3 (00011)
  - Format: `sc.w rd, rs2, (rs1)`
  - Effect: Stores word from rs2 to address in rs1 if reservation is valid
  - Returns: 0 in rd on success, 1 on failure

### Reservation Logic
Each core maintains one reservation at a time. The reservation is:
- Set by LR instruction
- Cleared by SC instruction (regardless of success)
- Invalidated when another core writes to the reserved address
- Checked by SC instruction to determine success

## Test Program
A test program `test_atomic.c` has been provided that demonstrates atomic increment using LR/SC:

```c
int atomic_increment(volatile int* addr) {
    int old_value, new_value, result;
    
    do {
        __asm__ volatile ("lr.w %0, (%1)\n" : "=r"(old_value) : "r"(addr) : "memory");
        new_value = old_value + 1;
        __asm__ volatile ("sc.w %0, %2, (%1)\n" : "=r"(result) : "r"(addr), "r"(new_value) : "memory");
    } while (result != 0);
    
    return old_value;
}
```

## Building and Running Tests

### Prerequisites
- RISC-V toolchain with RV32IMA support (rv32ima architecture)
- The compiler must be configured with `-march=rv32ima` to enable atomic instructions

### Build Commands
```bash
# To build the test program instead of main.c:
make clean
cp test_atomic.c main.c.backup
cp main.c main.c.original
cp test_atomic.c main.c
make prog
```

### Running Simulation
```bash
# With display emulator:
make drun

# Without display emulator:
make run
```

### Expected Results
- The test runs 4 cores, each incrementing a shared counter 100 times
- Expected final counter value: 400 (4 cores × 100 increments)
- Display should show "PASS" if the counter equals 400

## Manual Verification

### Without a Toolchain
If you don't have access to a RISC-V toolchain with atomic support, you can manually verify the implementation by:

1. Checking the instruction decode logic in `proc.v`:
   - Verify AMO instructions (opcode 0x2F) are recognized in `pre_decoder`
   - Verify LR/SC are decoded correctly in the `decoder` module

2. Examining the reservation logic in `main.v`:
   - Each core has `reservation_valid` and `reservation_addr` registers
   - LR sets the reservation
   - SC checks and clears the reservation
   - Writes from other cores invalidate reservations

3. Tracing through the pipeline:
   - LR behaves like a load but also triggers `lr_o` signal
   - SC behaves like a conditional store and uses `sc_success_i` signal
   - The load_unit returns 0/1 for SC based on `sc_success_i`

## Integration Notes

### Compiler Requirements
To use LR/SC instructions in C code, you need:
```bash
riscv32-unknown-elf-gcc -march=rv32ima -mabi=ilp32 ...
```

Note: The 'a' in rv32ima enables the atomic extension.

### Alternative: Using GCC Built-in Atomics
Instead of inline assembly, you can use GCC's built-in atomic functions which will automatically generate LR/SC instructions when compiled with `-march=rv32ima`:

```c
#include <stdatomic.h>

_Atomic int counter = 0;
atomic_fetch_add(&counter, 1);  // Compiles to LR/SC sequence
```

## Troubleshooting

### SC Always Fails
- Check that LR is executed before SC
- Verify reservation logic in `main.v` is correctly tracking addresses
- Ensure no intervening writes to the reserved address

### Unexpected Counter Value
- Verify all cores are executing the test
- Check for race conditions in non-atomic code paths
- Ensure the reservation invalidation logic is working correctly

### Build Errors
- Verify compiler supports rv32ima architecture
- Check that inline assembly syntax is correct
- Ensure all signal widths match (LSU_CTRL_WIDTH should be 8)
