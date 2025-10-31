/* Test program for RV32A LR/SC instructions */
#include "st7789.h"
#include "util.h"

#define NCORES 4

// Shared counter protected by LR/SC
volatile int shared_counter = 0;
volatile int test_results[NCORES] = {0, 0, 0, 0};

// Atomic increment using LR/SC
int atomic_increment(volatile int* addr) {
    int old_value, new_value, result;
    
    do {
        // LR.W: Load-Reserved Word
        // Syntax: lr.w rd, (rs1)
        __asm__ volatile (
            "lr.w %0, (%1)\n"
            : "=r"(old_value)
            : "r"(addr)
            : "memory"
        );
        
        new_value = old_value + 1;
        
        // SC.W: Store-Conditional Word
        // Syntax: sc.w rd, rs2, (rs1)
        // Returns 0 on success, 1 on failure
        __asm__ volatile (
            "sc.w %0, %2, (%1)\n"
            : "=r"(result)
            : "r"(addr), "r"(new_value)
            : "memory"
        );
        
    } while (result != 0);  // Retry if SC failed
    
    return old_value;
}

int main() {
    int hart_id = pg_hart_id();
    int i;
    
    // Each core increments the shared counter 100 times
    for (i = 0; i < 100; i++) {
        atomic_increment(&shared_counter);
    }
    
    // Mark this hart as done
    test_results[hart_id] = 1;
    
    // Hart 0 waits for all cores and displays result
    if (hart_id == 0) {
        // Wait for all cores to finish
        while (test_results[0] == 0 || test_results[1] == 0 || 
               test_results[2] == 0 || test_results[3] == 0) {
            // Wait
        }
        
        // Display result
        pg_lcd_set_pos(0, 0);
        pg_lcd_prints("LR/SC Test");
        pg_lcd_set_pos(0, 1);
        pg_lcd_prints("Counter:");
        pg_lcd_set_pos(0, 2);
        pg_lcd_printd(shared_counter);
        pg_lcd_set_pos(0, 3);
        
        // Expected: 400 (4 cores * 100 increments each)
        if (shared_counter == 400) {
            pg_lcd_prints("PASS");
        } else {
            pg_lcd_prints("FAIL");
        }
    }
    
    // Infinite loop
    while (1) {
        // Nothing
    }
    
    return 0;
}
