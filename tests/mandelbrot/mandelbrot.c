/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

#include <stdio.h>
#include "st7789.h"
#include "util.h"
#include "atomic.h"
#include "perf.h"

#ifndef NCORES
#define NCORES 4       // number of cores
#endif

#define X_PIX  240     // display width
#define Y_PIX  240     // display height
#define ROWS_PER_CORE (Y_PIX / NCORES)
#define ITER_MAX 256
#define COUNT_MAX 100

#define USE_LCD 0

#if USE_LCD
#define prints pg_lcd_prints_8x8
#define draw_point pg_lcd_draw_point
#define printd pg_lcd_printd
#else
#define prints pg_prints
#define draw_point
#define printd pg_printd
#endif

// Shared variables
volatile float x_min = 0.270851;
volatile float x_max = 0.270900;
volatile float y_min = 0.004641;
volatile float y_max = 0.004713;

volatile int current_row = 1; // between 1 and Y_PIX

void draw_pixel(int x, int y, int k)
{
    int color = ((k & 0x7f) << 11) ^ ((k & 0x7f) << 7) ^ (k & 0x7f);
    draw_point(x, y, color);
}

static inline unsigned int cfu_op(unsigned int funct7, unsigned int funct3,
                                  unsigned int rs1, unsigned int rs2,
                                  unsigned int* rd) {
    unsigned int result;
    asm volatile(
        ".insn r CUSTOM_0, %3, %4, %0, %1, %2"
        : "=r"(result)
        : "r"(rs1), "r"(rs2), "i"(funct3), "i"(funct7)
        :
    );
    *rd = result;
}

void mandelbrot(int row)
{
    float dx = (x_max - x_min) / X_PIX;
    float dy = (y_max - y_min) / Y_PIX;

    float y = y_min + row * dy;

    for (int i = 1; i <= X_PIX; i++) {
        int k = 0;
        float x = x_min + i * dx;
#ifdef USE_HLS
        cfu_op(
            0,
            0,
            *(unsigned int*)&x,
            *(unsigned int*)&y,
            (unsigned int*)&k
        );
#else
        float u  = 0.0;
        float v  = 0.0;
        float u2 = 0.0;
        float v2 = 0.0;
        for (k = 1; k < ITER_MAX; k++) {
            v = 2 * u * v + y;
            u = u2 - v2 + x;
            u2 = u * u;
            v2 = v * v;
            if (u2 + v2 >= 4.0) break;
        };
#endif
        draw_pixel(i, row, k);
    }
}

int main()
{
    int hart_id = pg_hart_id();

    int cnt = 0;
    float delta = 0.00000300;

    pg_perf_disable();
    pg_perf_reset();
    pg_perf_enable();

    while (1) {
        if (hart_id == 0) {
            cnt++;

            if (cnt % 512 == 0) {
                delta *= -1;
            }

            x_max += delta;
            y_max += delta;
        }

        pg_barrier();
        while (1) {
            int row = atomic_fetch_add(&current_row, 1);
            if (row > Y_PIX) {
                break;
            }
            mandelbrot(row);
        }
        pg_barrier();

        if (hart_id == 0) {
            pg_lcd_set_pos(0, 14);
            printd(cnt);
            prints("\n");
            current_row = 1;
        }

#ifdef COUNT_MAX
        if (cnt >= COUNT_MAX) {
            break;
        }
#endif
    }
    unsigned long long cycle = pg_perf_cycle();
    char buf[64];
    if (hart_id == 0) {
        sprintf(buf, "cycle      : %15lld  \n", cycle);
        prints(buf);
    }

    pg_barrier();

    return 0;
}
