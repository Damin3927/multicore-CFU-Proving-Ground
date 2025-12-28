#include "atomic.h"
#include "st7789.h"
#include "util.h"

#ifndef NCORES
#define NCORES 4       // number of cores
#endif

#define INIT_COUNTER 1
#define ITERATIONS 100

volatile int shared_counter = INIT_COUNTER;  // Shared counter

int main()
{
    int hart_id = pg_hart_id();

    // Each core increments the shared counter ITERATIONS times
    for (int i = 0; i < ITERATIONS; i++) {
        atomic_add(&shared_counter, 1);
    }

    pg_barrier();

    if (hart_id == 0) {
        // Display the result
        pg_lcd_set_pos(0, 0);
        pg_lcd_prints("LR/SC Test");
        pg_lcd_set_pos(0, 1);
        pg_lcd_prints("Counter:");
        pg_lcd_set_pos(0, 2);
        pg_lcd_printd(shared_counter);
        pg_lcd_set_pos(0, 3);

        if (shared_counter == NCORES * ITERATIONS + INIT_COUNTER) {
            pg_lcd_prints("PASS");
        } else {
            pg_lcd_prints("FAIL");
        }
    }

    pg_barrier();

    return 0;
}
