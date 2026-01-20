#include "test_common.h"

#include <stdlib.h>

static volatile int fetch_add_counter;
static volatile int fetch_add_results[NCORES];
static volatile int add_counter;

test_result_t test_fetch_add_basic(int hart_id, int ncores)
{
    test_result_t result = {.name = "fetch_add_basic", .passed = 0, .failed = 0};

    if (hart_id == 0) {
        fetch_add_counter = 0;

        int old = atomic_fetch_add(&fetch_add_counter, 5);
        TEST_ASSERT_EQ(0, old, &result, "first fetch_add should return 0");
        TEST_ASSERT_EQ(5, fetch_add_counter, &result, "counter should be 5");

        old = atomic_fetch_add(&fetch_add_counter, 3);
        TEST_ASSERT_EQ(5, old, &result, "second fetch_add should return 5");
        TEST_ASSERT_EQ(8, fetch_add_counter, &result, "counter should be 8");

        old = atomic_fetch_add(&fetch_add_counter, 0);
        TEST_ASSERT_EQ(8, old, &result, "fetch_add with 0 should return 8");
        TEST_ASSERT_EQ(8, fetch_add_counter, &result, "counter should still be 8");
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);
    return result;
}

test_result_t test_fetch_add_100000(int hart_id, int ncores)
{
    test_result_t result = {.name = "fetch_add_100000", .passed = 0, .failed = 0};
    const int ITERATIONS = 100000;

    if (hart_id == 0) {
        fetch_add_counter = 0;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    for (int i = 0; i < ITERATIONS; i++) {
        atomic_fetch_add(&fetch_add_counter, 1);
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    if (hart_id == 0) {
        int expected = ncores * ITERATIONS;
        TEST_ASSERT_EQ(expected, fetch_add_counter, &result, "counter should equal ncores*1000");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

test_result_t test_fetch_add_1000_random_nop(int hart_id, int ncores)
{
    test_result_t result = {.name = "fetch_add_1000_random_nop", .passed = 0, .failed = 0};
    const int ITERATIONS = 1000;

    if (hart_id == 0) {
        fetch_add_counter = 0;
        srand(42);
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    for (int i = 0; i < ITERATIONS; i++) {
        atomic_fetch_add(&fetch_add_counter, 1);

        int nop_count = rand() % 100; // Random NOPs between 0-99
        for (int j = 0; j < nop_count; j++) {
            asm volatile("nop");
        }
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    if (hart_id == 0) {
        int expected = ncores * ITERATIONS;
        TEST_ASSERT_EQ(expected, fetch_add_counter, &result,
                       "counter should equal ncores*1000 with random NOPs");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}
