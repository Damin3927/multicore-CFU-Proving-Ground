/* Test program for RV32A LR/SC instructions */
#include "st7789.h"
#include "util.h"

#ifndef NCORES
#define NCORES 4       // number of cores
#endif

#define INIT_COUNTER 15

volatile int shared_counter = INIT_COUNTER;  // Shared counter
volatile int test_results[NCORES] = {0}; // Test results from each core

void atomic_increment() {
    int old_val, new_val, ret;
    do {
        asm volatile (
            "lr.w %0, (%2)\n"
            "addi %1, %0, 1\n"
            "sc.w %0, %1, (%2)\n"
            : "=&r"(ret), "=&r"(new_val)
            : "r"(&shared_counter)
            : "memory"
        );
    } while (ret != 0);
}

int main()
{
    int hart_id = pg_hart_id();

    // Each core increments the shared counter 100 times
    for (int i = 0; i < 100; i++) {
        atomic_increment();
    }

    // Mark this hart as done
    test_results[hart_id] = 1;

    // Hart 0 waits for all cores and displays result
    if (hart_id == 0) {
        // Wait for all cores to finish
        while (test_results[0] == 0 || test_results[1] == 0 || test_results[2] == 0 || test_results[3] == 0) {}

        // Display result
        pg_lcd_set_pos(0, 0);
        pg_lcd_prints("LR/SC Test");
        pg_lcd_set_pos(0, 1);
        pg_lcd_prints("Counter:");
        pg_lcd_set_pos(0, 2);
        pg_lcd_printd(shared_counter);
        pg_lcd_set_pos(0, 3);

        // Expected: 400 (4 cores * 100 increments each)
        if (shared_counter == NCORES * 100 + INIT_COUNTER) {
            pg_lcd_prints("PASS");
        } else {
            pg_lcd_prints("FAIL");
        }
    }

    while (1) {}
}
