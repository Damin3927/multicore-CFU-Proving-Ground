/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

#include "st7789.h"
#include "util.h"

volatile int *tmp = (int *)0x10001000; // Shared memory address

int main() {
  int hart_id = pg_hart_id();

  if (hart_id == 0) {
    pg_lcd_set_pos(0, 0);
    pg_lcd_prints("Hart 0 works!");

    while (1) {
      if (*tmp == 1) {
        break;
      }
    }
    pg_lcd_set_pos(0, 1);
    pg_lcd_prints("Hart 1 woke me up!");
  } else if (hart_id == 1) {
    *tmp = 1;
  }

  while (1)
    ;
}
