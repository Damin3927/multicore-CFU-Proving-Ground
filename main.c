/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

#include "st7789.h"
#include "util.h"

#define USE_HLS

#define NCORES 4       // number of cores
#define X_PIX  240     // display width
#define Y_PIX  240     // display height
#define ROWS_PER_CORE (Y_PIX / NCORES)
#define ITER_MAX 256

// Shared variables
volatile float x_min = 0.270851;
volatile float x_max = 0.270900;
volatile float y_min = 0.004641;
volatile float y_max = 0.004713;
volatile int frame_ready[NCORES] = {0, 0, 0, 0};
volatile int frame_done[NCORES] = {0, 0, 0, 0};

void draw_pixel(int x, int y, int k)
{
    int color = ((k & 0x7f) << 11) ^ ((k & 0x7f) << 7) ^ (k & 0x7f);
    pg_lcd_draw_point(x, y, color);
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

void mandelbrot(int start_row, int end_row)
{
    float dx = (x_max - x_min) / X_PIX;
    float dy = (y_max - y_min) / Y_PIX;

    for (int j = start_row; j <= end_row; j++) {
        float y = y_min + j * dy;

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
            draw_pixel(i, j, k);
        }
    }
}

int main()
{
    int hart_id = pg_hart_id();

    // Calculate row range for this hart
    int start_row = hart_id * ROWS_PER_CORE + 1;
    int end_row = (hart_id + 1) * ROWS_PER_CORE;

    int cnt = 0;
    float delta = 0.00000300;

    while (1) {
        // Hart 0 is the master
        // Updates parameters and coordinates
        if (hart_id == 0) {
            cnt++;

            if (cnt % 512 == 0) {
                delta *= -1;
            }

            x_max += delta;
            y_max += delta;

            // Signal all harts to start
            for (int i = 0; i < NCORES; i++) {
                frame_ready[i]++;
            }
        } else {
            // Worker harts wait for frame counter to change
            while (frame_ready[hart_id] == 0);
        }

        frame_ready[hart_id]--;

        mandelbrot(start_row, end_row);

        frame_done[hart_id]++;

        // Only hart 0 updates display when all harts have finished
        if (hart_id == 0) {
            for (int i = 0; i < NCORES; i++) {
                while (frame_done[i] == 0);
                frame_done[i]--;
            }
            pg_lcd_set_pos(0, 14);
            pg_lcd_printd(cnt);
        }
    }
    return 0;
}
