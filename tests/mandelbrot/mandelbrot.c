#include "atomic.h"
#include "perf.h"
#include "st7789.h"
#include "util.h"

#include <stdio.h>

#ifndef NCORES
#define NCORES 4 // number of cores
#endif

#define X_PIX 240 // display width
#define Y_PIX 240 // display height
#define ITER_MAX 256
#define COUNT_MAX 5

#define USE_LCD 0

#if USE_LCD
#define prints pg_lcd_prints_8x8
#define draw_point pg_lcd_draw_point
#define printd pg_lcd_printd
#else
#define prints pg_prints
volatile int dummy_sink;
static inline void draw_point(int x, int y, int c)
{
    dummy_sink = x + y + c;
} // Avoid optimization
#define printd pg_printd
#endif

#define VERIFY_RESULT 0

// Shared variables
volatile int current_row = 1; // between 1 and Y_PIX

#if VERIFY_RESULT
volatile int[X_PIX][Y_PIX] current_draw_result;
#endif

void draw_pixel(int x, int y, int k)
{
    int color = ((k & 0x7f) << 11) ^ ((k & 0x7f) << 7) ^ (k & 0x7f);
    draw_point(x, y, color);
#if VERIFY_RESULT
    current_draw_result[x - 1][y - 1] = color;
#endif
}

static inline unsigned int cfu_op(unsigned int funct7, unsigned int funct3, unsigned int rs1,
                                  unsigned int rs2, unsigned int *rd)
{
    unsigned int result;
    asm volatile(".insn r CUSTOM_0, %3, %4, %0, %1, %2"
                 : "=r"(result)
                 : "r"(rs1), "r"(rs2), "i"(funct3), "i"(funct7)
                 :);
    *rd = result;
}

void mandelbrot(int row, float x_max, float y_max)
{
    float x_min = 0.270851;
    float y_min = 0.004641;

    float dx = (x_max - x_min) / X_PIX;
    float dy = (y_max - y_min) / Y_PIX;

    float y = y_min + row * dy;

    for (int i = 1; i <= X_PIX; i++) {
        int k = 0;
        float x = x_min + i * dx;
#ifdef USE_HLS
        cfu_op(0, 0, *(unsigned int *) &x, *(unsigned int *) &y, (unsigned int *) &k);
#else
        float u = 0.0;
        float v = 0.0;
        float u2 = 0.0;
        float v2 = 0.0;
        for (k = 1; k < ITER_MAX; k++) {
            v = 2 * u * v + y;
            u = u2 - v2 + x;
            u2 = u * u;
            v2 = v * v;
            if (u2 + v2 >= 4.0)
                break;
        };
#endif
        draw_pixel(i, row, k);
    }
}

int main(void)
{
    int hart_id = pg_hart_id();

    int cnt = 0;
    float delta = 0.00000300;
    float x_max = 0.270900;
    float y_max = 0.004713;

    pg_perf_disable();
    pg_perf_reset();
    pg_perf_enable();

    while (1) {
        cnt++;

        if (cnt % 512 == 0) {
            delta *= -1;
        }

        x_max += delta;
        y_max += delta;

        pg_barrier();
        while (1) {
            int row = atomic_fetch_add(&current_row, 1);
            if (row > Y_PIX) {
                break;
            }
            mandelbrot(row, x_max, y_max);
        }
        pg_barrier();

        if (hart_id == 0) {
            pg_lcd_set_pos(0, 14);
            printd(cnt);
            prints("\n");
            current_row = 1;
#if VERIFY_RESULT
            prints("COUNT ");
            printd(cnt);
            prints(" RESULT:\n");

            for (int x = 1; x <= X_PIX; x++) {
                for (int y = 1; y <= Y_PIX; y++) {
                    printd(current_draw_result[x - 1][y - 1]);
                    prints(" ");
                }
                prints("\n");
            }
#endif
        }

#ifdef COUNT_MAX
        if (cnt >= COUNT_MAX) {
            break;
        }
#endif
    }
    if (hart_id == 0) {
        unsigned long long cycle = pg_perf_cycle();
        char buf[64];
        sprintf(buf, "cycle      : %15lld  \n", cycle);
        prints(buf);
    }

    pg_barrier();

    return 0;
}
