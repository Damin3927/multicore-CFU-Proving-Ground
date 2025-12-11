#include <math.h>
#include "atomic.h"
#include "st7789.h"
#include "util.h"
#include "perf.h"

#ifndef NCORES
#define NCORES 4       // number of cores
#endif

#define M_PI		3.14159265358979323846	/* pi */

#define SAMPLE_RATE 44100
#define SIN_FREQ 440

#define FFT_POINT   1024
#define FFT_POINT_2 512
#define FFT_STAGES  10

static float W_N[2*FFT_POINT];
static float f[2*FFT_POINT];

void fft(float *f, int hart_id, int ncores)
{
    int block_offset = 2;
    int butterflies_offset = 1;

    for (int cnt_stages = 0; cnt_stages < FFT_STAGES; ++cnt_stages) {
        int num_blocks = FFT_POINT_2 >> cnt_stages;

        int blocks_per_core = num_blocks / ncores;
        int divide_by_block = num_blocks >= 4;
        int block_start, block_end;
        if (divide_by_block) {
            block_start = hart_id * blocks_per_core;
            block_end = block_start + blocks_per_core;
        } else {
            block_start = 0;
            block_end = num_blocks;
        }

        for (int cnt_blocks = block_start; cnt_blocks < block_end; ++cnt_blocks) {
            int cnt_twiddle = 0;
            int idx_blocks = cnt_blocks * block_offset;

            int cnt_butterflies_start, cnt_butterflies_end;
            if (divide_by_block) {
                cnt_butterflies_start = 0;
                cnt_butterflies_end = (1 << cnt_stages);
            } else {
                int butterflies_per_core = (1 << cnt_stages) / ncores;
                cnt_butterflies_start = hart_id * butterflies_per_core;
                cnt_butterflies_end = cnt_butterflies_start + butterflies_per_core;
            }

            for (int cnt_butterflies = cnt_butterflies_start; cnt_butterflies < cnt_butterflies_end; ++cnt_butterflies) {
                int idx_upper = idx_blocks + cnt_butterflies;
                int idx_lower = idx_upper + butterflies_offset;

                float temp_var1 = f[(idx_lower<<1)]   * W_N[(cnt_twiddle<<1)]  ;
                float temp_var2 = f[(idx_lower<<1)+1] * W_N[(cnt_twiddle<<1)+1];
                float temp_var3 = f[(idx_lower<<1)]   * W_N[(cnt_twiddle<<1)+1];
                float temp_var4 = f[(idx_lower<<1)+1] * W_N[(cnt_twiddle<<1)]  ;
                float temp_var1_2 = temp_var1 - temp_var2;
                float temp_var3_4 = temp_var3 + temp_var4;

                float real = f[(idx_upper<<1)];
                float imag = f[(idx_upper<<1)+1];

                f[(idx_upper<<1)]   = real + temp_var1_2;
                f[(idx_upper<<1)+1] = imag + temp_var3_4;
                f[(idx_lower<<1)]   = real - temp_var1_2;
                f[(idx_lower<<1)+1] = imag - temp_var3_4;

                cnt_twiddle += (FFT_POINT_2 >> cnt_stages);
            }
        }

        pg_barrier();

        block_offset <<= 1;
        butterflies_offset <<= 1;
    }
}

int main ()
{
    int hart_id = pg_hart_id();

    float t;

    int i_start = (FFT_POINT / NCORES) * hart_id;
    int i_end = i_start + (FFT_POINT / NCORES);

    for (int i = i_start; i < i_end; i++) {
        W_N[(i<<1)]   = cosf(-2.0 * M_PI * i / FFT_POINT);
        W_N[(i<<1)+1] = sinf(-2.0 * M_PI * i / FFT_POINT);

        t = 1.0 * i / SAMPLE_RATE;
        f[(i<<1)] = sinf(2.0 * M_PI * SIN_FREQ * t);
        f[(i<<1)+1] = 0;
    }

    pg_barrier();

    int j;
    float tmp;
    for (int i = i_start; i < i_end; i++) {
        j = ((i & 0xFF00) >> 8) | ((i & 0x00FF) << 8);
        j = ((j & 0xF0F0) >> 4) | ((j & 0x0F0F) << 4);
        j = ((j & 0xCCCC) >> 2) | ((j & 0x3333) << 2);
        j = ((j & 0xAAAA) >> 1) | ((j & 0x5555) << 1);
        j >>= (16 - FFT_STAGES);

        if (i < j) {
            tmp = f[i<<1];
            f[i<<1] = f[j<<1];
            f[j<<1] = tmp;
        }
    }

    unsigned long long start;
    if (hart_id == 0) {
        pg_perf_reset();
        start = pg_perf_cycle();
        pg_perf_enable();
    }
    pg_barrier();

    fft(f, hart_id, NCORES);

    if (hart_id == 0) {
        pg_perf_disable();
        unsigned long long end = pg_perf_cycle();
        unsigned long long cycles = end - start;
        pg_prints("FFT cycles:\n");
        pg_printd(cycles);
    }

    pg_barrier();

    return 0;
}
