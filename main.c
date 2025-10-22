/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

#include "st7789.h"
#include "util.h"

#define TEST_SIZE 100  // Number of words to test per core

// Shared results
volatile int test_pass[4] = {0, 0, 0, 0};
volatile int barrier[4] = {0, 0, 0, 0};

int main() {
    int hart_id = pg_hart_id();

    // Each core gets its own memory region
    volatile int *mem = (int *)(0x10001000 + hart_id * 0x400);

    int errors = 0;

    // Test: Write values, then read them back
    for (int i = 0; i < TEST_SIZE; i++) {
        int value = (hart_id << 16) | i;  // Unique value per core
        mem[i] = value;  // Store (sw)
    }

    for (int i = 0; i < TEST_SIZE; i++) {
        int expected = (hart_id << 16) | i;
        int actual = mem[i];  // Load (lw)

        if (actual != expected) {
            errors++;
        }
    }

    // Store result
    test_pass[hart_id] = (errors == 0) ? 1 : 0;
    barrier[hart_id] = 1;

    // Hart 0 displays results
    if (hart_id == 0) {
        // Wait for all harts
        while (barrier[0] == 0 || barrier[1] == 0 ||
               barrier[2] == 0 || barrier[3] == 0);

        pg_lcd_set_pos(0, 0);
        pg_lcd_prints("LW/SW Test:");

        pg_lcd_set_pos(0, 1);
        pg_lcd_prints("H0:");
        pg_lcd_prints(test_pass[0] ? "PASS " : "FAIL ");
        pg_lcd_prints("H1:");
        pg_lcd_prints(test_pass[1] ? "PASS" : "FAIL");

        pg_lcd_set_pos(0, 2);
        pg_lcd_prints("H2:");
        pg_lcd_prints(test_pass[2] ? "PASS " : "FAIL ");
        pg_lcd_prints("H3:");
        pg_lcd_prints(test_pass[3] ? "PASS" : "FAIL");

        pg_lcd_set_pos(0, 3);
        if (test_pass[0] && test_pass[1] && test_pass[2] && test_pass[3]) {
            pg_lcd_prints("ALL PASS!");
        } else {
            pg_lcd_prints("FAIL");
        }
    }

    while (1);
}
