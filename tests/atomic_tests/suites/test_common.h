#ifndef TEST_COMMON_H
#define TEST_COMMON_H

#include "atomic.h"
#include "util.h"

#ifndef NCORES
#define NCORES 4
#endif

typedef struct {
    const char *name;
    int passed;
    int failed;
} test_result_t;

typedef test_result_t (*test_func_t)(int hart_id, int ncores);

#define TEST_ASSERT(cond, result, msg) do { \
    if (!(cond)) { \
        if ((result)->failed == 0) { \
            pg_prints("  FAIL: "); \
            pg_prints(msg); \
            pg_prints("\n"); \
        } \
        (result)->failed++; \
    } else { \
        (result)->passed++; \
    } \
} while(0)

#define TEST_ASSERT_EQ(expected, actual, result, msg) do { \
    if ((expected) != (actual)) { \
        if ((result)->failed == 0) { \
            pg_prints("  FAIL: "); \
            pg_prints(msg); \
            pg_prints(" expected="); \
            pg_printd(expected); \
            pg_prints(" actual="); \
            pg_printd(actual); \
            pg_prints("\n"); \
        } \
        (result)->failed++; \
    } else { \
        (result)->passed++; \
    } \
} while(0)

/* Barrier IDs for tests */
enum TestBarriers {
    BARRIER_TEST_SETUP = 0,
    BARRIER_TEST_RUN = 1,
    BARRIER_TEST_VERIFY = 2,
    BARRIER_TEST_CLEANUP = 3,
};

test_result_t test_fetch_add_basic(int hart_id, int ncores);
test_result_t test_fetch_add_negative(int hart_id, int ncores);
test_result_t test_fetch_add_100(int hart_id, int ncores);
test_result_t test_fetch_add_1000(int hart_id, int ncores);
test_result_t test_fetch_add_1000_random_nop(int hart_id, int ncores);

test_result_t test_exchange_basic(int hart_id, int ncores);
test_result_t test_exchange_concurrent(int hart_id, int ncores);
test_result_t test_exchange_concurrent_50(int hart_id, int ncores);

test_result_t test_barrier_simple(int hart_id, int ncores);
test_result_t test_barrier_multiple(int hart_id, int ncores);

test_result_t test_mixed_atomic_ops(int hart_id, int ncores);
test_result_t test_producer_consumer(int hart_id, int ncores);
test_result_t test_spinlock(int hart_id, int ncores);
test_result_t test_cas_single(int hart_id, int ncores);
test_result_t test_cas_retry(int hart_id, int ncores);

#endif /* TEST_COMMON_H */
