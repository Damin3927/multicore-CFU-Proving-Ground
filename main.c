/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

#include <stdlib.h>
#include "atomic.h"
#include "st7789.h"
#include "perf.h"
#include "util.h"

#ifndef NCORES
#define NCORES 4 // number of cores
#endif

volatile int count = 0;
volatile spinlock_t lock = 0;

void RandomChar() {
    while (1) {
        int x = rand() % 240;
        int y = rand() % 240;
        char c = 'A' + rand() % 26;
        char color = rand() & 0x7;

        spinlock_acquire(&lock);

        count++;

        pg_lcd_draw_char(x, y, c, color, 1);
        pg_lcd_set_pos(0, 14);
        pg_lcd_prints("steps :");
        pg_lcd_printd(count);

        spinlock_release(&lock);
    }
}

int main () {
    int hart_id = pg_hart_id();
    if (hart_id != 0) {
        pg_lcd_reset();
    }
    RandomChar();
    return 0;
}
