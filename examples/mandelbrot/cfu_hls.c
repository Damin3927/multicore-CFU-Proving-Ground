#include <string.h>

#define ITER_MAX 256

void cfu_hls(
    char   funct3_i,
    char   funct7_i,
    int    src1_i  ,
    int    src2_i  ,
    int*   rslt_o  ) {

    float x;
    memcpy(&x, &src1_i, sizeof(float));
    float y;
    memcpy(&y, &src2_i, sizeof(float));

    float u  = 0.0;
    float v  = 0.0;
    float u2 = 0.0;
    float v2 = 0.0;
    int k;
    for (k = 1; k < ITER_MAX; k++) {
        v = 2 * u * v + y;
        u = u2 - v2 + x;
        u2 = u * u;
        v2 = v * v;
        if (u2 + v2 >= 4.0) break;
    };
    *rslt_o = k;
}
