/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

#include "st7789.h"
#include "util.h"

#ifndef NCORES
#define NCORES 4       // number of cores
#endif

volatile int shared_var = 0;

int main()
{
    int hart_id = pg_hart_id();

    shared_var = hart_id;

    if (hart_id == 0) {
        pg_lcd_prints("Shared Variable Test: ");
        pg_lcd_printd(shared_var);
    }

    while (1);

    return 0;
}
