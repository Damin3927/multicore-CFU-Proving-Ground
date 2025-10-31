# RV32A LR/SC Implementation Summary

## Overview
This document summarizes the implementation of Load-Reserved (LR.W) and Store-Conditional (SC.W) instructions from the RISC-V RV32A atomic extension for the multicore CFU Proving Ground processor.

## Architecture Overview
The implementation adds hardware support for atomic operations through a reservation-based mechanism. Each of the 4 CPU cores maintains its own reservation state, which is tracked centrally in the memory subsystem.

## Key Design Decisions

### 1. Instruction Encoding
Following the RISC-V specification:
- **Opcode**: 0x2F (0101111) - AMO instruction class
- **funct3**: 0x2 (010) - Word size operations
- **funct5**: 
  - 0x2 (00010) for LR.W
  - 0x3 (00011) for SC.W

### 2. Reservation Mechanism
- **One reservation per core**: Each core can have at most one active reservation
- **Word-aligned addresses**: Reservations are tracked at word granularity (ignoring bits [1:0])
- **Automatic invalidation**: A reservation is invalidated when:
  - Another core writes to the same word-aligned address
  - The owning core executes an SC instruction (regardless of success)
  - The core is reset

### 3. Pipeline Integration
The implementation integrates with the existing 5-stage pipeline (IF, ID, EX, MA, WB):

#### Instruction Decode (ID) Stage:
- `pre_decoder` recognizes AMO instructions (opcode 0x2F)
- `decoder` identifies LR/SC based on funct5 and funct3 fields
- LSU control signals extended to include IS_LR and IS_SC flags

#### Execution (EX) Stage:
- `store_unit` generates address from rs1 (no immediate offset for LR/SC)
- `store_unit` outputs lr_o and sc_o signals
- `store_unit` conditionally enables write for SC based on sc_success_i

#### Memory Access (MA) Stage:
- Reservation logic in main.v checks validity
- `load_unit` returns success/failure status for SC instructions
- Memory write occurs only if SC reservation is valid

## Modified Files

### 1. config.vh
Added control signal definitions:
```verilog
`define LSU_CTRL_IS_LR 6
`define LSU_CTRL_IS_SC 7
`define LSU_CTRL_WIDTH 8  // Extended from 6 to 8
```

### 2. proc.v

#### pre_decoder Module:
- Added AMO instruction type recognition (opcode 5'b01011)

#### decoder Module:
- Extracts funct5 field for AMO instruction decoding
- Generates lsu_c6 (IS_LR) when op=0x17 && f5=0x2 && f3=0x2
- Generates lsu_c7 (IS_SC) when op=0x17 && f5=0x3 && f3=0x2
- LR treated as load, SC treated as conditional store

#### cpu Module:
- Added ports: lr_o, sc_o (outputs), sc_success_i (input)

#### store_unit Module:
- Added sc_success_i input port
- LR/SC use rs1 directly (no immediate offset)
- dbus_wvalid_o conditional: `(!w_is_sc || sc_success_i)`
- Outputs lr_o and sc_o signals

#### load_unit Module:
- Added sc_success_i input port
- Returns 0 on SC success, 1 on SC failure
- Normal load behavior unchanged

### 3. main.v

#### Reservation State:
```verilog
reg reservation_valid [0:NCORES-1];  // One reservation per core
reg [31:0] reservation_addr [0:NCORES-1];  // Word-aligned address
```

#### Reservation Logic:
1. **On LR**: Set reservation_valid, store word-aligned address
2. **On SC**: Clear reservation_valid (regardless of success)
3. **On conflicting write**: Invalidate reservations with matching addresses

#### SC Success Determination:
```verilog
sc_success[i] = reservation_valid[i] && 
                (dbus_addr[i][31:2] == reservation_addr[i][31:2])
```

#### CPU Instantiation:
Each CPU core connected with lr_sig, sc_sig, and sc_success signals

## Verification

### Functional Correctness
The implementation satisfies the RISC-V specification requirements:
1. ✅ LR loads a word and sets a reservation
2. ✅ SC stores conditionally based on reservation validity
3. ✅ SC returns 0 on success, 1 on failure
4. ✅ Reservations are invalidated by intervening stores
5. ✅ Word-aligned address comparison

### Test Program
`test_atomic.c` provides a multicore test:
- 4 cores each increment a shared counter 100 times
- Uses LR/SC for atomic increment
- Expected result: counter = 400
- Verifies correct atomic operation across cores

## Performance Considerations

### Strengths:
- Minimal hardware overhead (one reservation per core)
- No stalling for LR instructions
- Parallel execution of non-conflicting atomic operations

### Potential Optimizations:
1. Could add address-range reservations instead of exact word matching
2. Could implement early reservation invalidation on context switch
3. Could add performance counters for SC failure rates

## Limitations

### Current Implementation:
- Only LR.W and SC.W (word-sized) implemented
- No support for LR.D/SC.D (doubleword) - not needed for RV32
- No support for other AMO operations (AMOSWAP, AMOADD, etc.)
- No ordering (aq/rl) bit support - could be added in future

### Hardware Requirements:
- Requires 4-core configuration as currently implemented
- Reservation logic scales linearly with number of cores
- Each core-to-core write comparison adds combinational logic

## Integration Notes

### Compiler Support:
Requires RISC-V toolchain with `-march=rv32ima` or `-march=rv32ia`:
```bash
riscv32-unknown-elf-gcc -march=rv32ima -mabi=ilp32 ...
```

### C/C++ Atomic Operations:
GCC/Clang will automatically generate LR/SC sequences for:
```c
#include <stdatomic.h>
atomic_int counter;
atomic_fetch_add(&counter, 1);  // Compiles to LR/SC
```

### Inline Assembly:
Direct use via inline assembly:
```c
int value, result;
__asm__ volatile ("lr.w %0, (%1)" : "=r"(value) : "r"(addr) : "memory");
__asm__ volatile ("sc.w %0, %2, (%1)" : "=r"(result) : "r"(addr), "r"(new_val) : "memory");
```

## Future Extensions

### Potential Additions:
1. **Other AMO instructions**: AMOSWAP, AMOADD, AMOAND, AMOOR, AMOXOR, AMOMAX, AMOMIN
2. **Ordering bits**: Support aq (acquire) and rl (release) semantics
3. **LR/SC statistics**: Hardware counters for success/failure rates
4. **Cache coherence**: Integration with future cache implementation
5. **AXI support**: Atomic transactions on external bus interfaces

### Backward Compatibility:
- All changes are additive - no existing functionality modified
- Processors continue to work with rv32im code
- New atomic instructions are opt-in through compiler flags

## References
- RISC-V Unprivileged ISA Specification, Version 20191213
- Chapter 8: "A" Standard Extension for Atomic Instructions
- Section 8.2: Load-Reserved/Store-Conditional Instructions
