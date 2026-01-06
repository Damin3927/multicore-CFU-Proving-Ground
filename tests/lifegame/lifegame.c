/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

#include <stdlib.h>
#include <stdio.h>
#include "st7789.h"
#include "perf.h"
#include "util.h"
#include "atomic.h"

#ifndef NCORES
#define NCORES 4
#endif

#define WIDTH 120
#define HEIGHT 120

#define STEPS 5 // small data set for test and debug

#define USE_LCD 0

#if USE_LCD
#define prints pg_lcd_prints_8x8
#define draw_point pg_lcd_draw_point
#else
#define prints pg_prints
#define draw_point
#endif

/*******************************************************************************/
void initialize(volatile int grid[HEIGHT][WIDTH])
{
    srand(7);
    for (int y = 0; y < HEIGHT; y++)
    {
        for (int x = 0; x < WIDTH; x++)
        {
            grid[y][x] = 0;
        }
    }
    for (int x = 10; x < 110; x++)
    {
        grid[x][60] = (rand() & 0xfffffff);
    }
    for (int y = 10; y < 110; y++)
    {
        grid[60][y] = (rand() & 0xfffffff);
    }

    for (int i = 10; i < 40; i++)
    {
        grid[i][i] = (rand() & 0xfffffff);
    }
    for (int i = 10; i < 40; i++)
    {
        grid[i + 1][i] = (rand() & 0xfffffff);
    }

    for (int i = 10; i < 70; i++)
    {
        grid[i][i + 80] = (rand() & 0xfffffff);
    }
    for (int i = 10; i < 70; i++)
    {
        grid[i + 1][i + 80] = (rand() & 0xfffffff);
    }

    for (int i = 10; i < 70; i++)
    {
        grid[i + 60][90] = (rand() & 0xfffffff);
    }
}
/*******************************************************************************/
void print_grid(volatile int grid[HEIGHT][WIDTH], int start_x, int end_x)
{
    for (int i = 0; i < HEIGHT; i++)
    {
        for (int j = start_x; j < end_x; j++)
        {
            int c = (grid[i][j] % 8);
            int color = (grid[i][j] == 0) ? PG_BLUE : (c == PG_BLACK) ? PG_WHITE
                                                  : (c == PG_BLUE)    ? PG_YELLOW
                                                                      : c;
            draw_point(i * 2, j * 2, color);
            draw_point(i * 2 + 1, j * 2, color);
            draw_point(i * 2, j * 2 + 1, color);
            draw_point(i * 2 + 1, j * 2 + 1, color);
        }
    }
}

/*******************************************************************************/
void count_neighbor(volatile int grid[HEIGHT][WIDTH],
                    int row, int col, int *count, int *sum)
{
    int liveNeighbors = 0;
    int NeighborSum = grid[row][col];
    for (int i = -1; i <= 1; i++)
    {
        for (int j = -1; j <= 1; j++)
        {
            if (i == 0 && j == 0)
                continue;

            int neighborRow = (row + i + HEIGHT) % HEIGHT;
            int neighborCol = (col + j + WIDTH) % WIDTH;

            liveNeighbors += (grid[neighborRow][neighborCol] != 0);
            NeighborSum += grid[neighborRow][neighborCol];
        }
    }
    *count = liveNeighbors;
    *sum = NeighborSum;
}

/*******************************************************************************/
void update_grid(volatile int cGrid[HEIGHT][WIDTH], volatile int nGrid[HEIGHT][WIDTH], int start_x, int end_x)
{
    for (int i = 0; i < HEIGHT; i++)
    {
        for (int j = start_x; j < end_x; j++)
        {
            int liveNeighbors;
            int sum;
            count_neighbor(cGrid, i, j, &liveNeighbors, &sum);

            if (cGrid[i][j] != 0)
            {
                if (liveNeighbors < 2 || liveNeighbors > 3)
                {
                    nGrid[i][j] = 0;
                }
                else
                {
                    nGrid[i][j] = sum;
                }
            }
            else
            {
                if (liveNeighbors == 3)
                {
                    nGrid[i][j] = sum;
                }
                else
                {
                    nGrid[i][j] = 0;
                }
            }
        }
    }
}

/*******************************************************************************/
volatile int grid[HEIGHT][WIDTH];  // grid
volatile int nGrid[HEIGHT][WIDTH]; // next grid

enum Barriers {
    INITIALIZE,
    UPDATE_GRID,
    UPDATE_NEXT,
};

int main_worker(int start_x, int end_x, int hart_id) {
    pg_barrier_at(INITIALIZE, NCORES);

    for (int step = 0; step < STEPS; step++)
    {
        print_grid(grid, start_x, end_x);

        update_grid(grid, nGrid, start_x, end_x);
        pg_barrier_at(UPDATE_GRID, NCORES);

        for (int i = 0; i < HEIGHT; i++)
        {
            for (int j = start_x; j < end_x; j++)
            {
                grid[i][j] = nGrid[i][j];
            }
        }

        pg_barrier_at(UPDATE_NEXT, NCORES);
    }

    return 0;
}

int main_master(int start_x, int end_x) {
    pg_lcd_reset();
    char buf[64];

    initialize(grid);
    pg_barrier_at(INITIALIZE, NCORES);

    pg_perf_disable();
    pg_perf_reset();
    pg_perf_enable();
    int cnt = 0;

    for (int step = 0; step < STEPS; step++)
    {
        cnt++;
        print_grid(grid, start_x, end_x);

        pg_lcd_set_pos(240 - 60, 240 - 11);
        sprintf(buf, "%d\n", cnt);
        prints(buf);

        update_grid(grid, nGrid, start_x, end_x);
        pg_barrier_at(UPDATE_GRID, NCORES);

        for (int i = 0; i < HEIGHT; i++)
        {
            for (int j = start_x; j < end_x; j++)
            {
                grid[i][j] = nGrid[i][j];
            }
        }

        pg_barrier_at(UPDATE_NEXT, NCORES);
    }

    unsigned long long cycle = pg_perf_cycle();

    pg_lcd_set_pos(0, 0);
    prints("---------- finished ----------\n");
    sprintf(buf, "cycle      : %15lld  \n", cycle);
    prints(buf);
    prints("------------------------------\n");
    return 0;
}

int main()
{
    int hart_id = pg_hart_id();

    int start_x = hart_id * (WIDTH / NCORES);
    int end_x = hart_id + 1 == NCORES ? WIDTH : (hart_id + 1) * (WIDTH / NCORES);

    if (hart_id == 0) {
        main_master(start_x, end_x);
    } else {
        main_worker(start_x, end_x, hart_id);
    }
    pg_barrier();
    return 0;
}
/*******************************************************************************/
