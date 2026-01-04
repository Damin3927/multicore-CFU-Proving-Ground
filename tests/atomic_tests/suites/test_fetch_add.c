#include "test_common.h"
#include <stdlib.h>

/* Shared variables for tests */
static volatile int fetch_add_counter;
static volatile int fetch_add_results[NCORES];
static volatile int add_counter;

test_result_t test_fetch_add_basic(int hart_id, int ncores)
{
    test_result_t result = { .name = "fetch_add_basic", .passed = 0, .failed = 0 };

    if (hart_id == 0) {
        fetch_add_counter = 0;

        /* Test basic functionality */
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

test_result_t test_fetch_add_negative(int hart_id, int ncores)
{
    test_result_t result = { .name = "fetch_add_negative", .passed = 0, .failed = 0 };

    if (hart_id == 0) {
        fetch_add_counter = 100;

        int old = atomic_fetch_add(&fetch_add_counter, -10);
        TEST_ASSERT_EQ(100, old, &result, "fetch_add(-10) should return 100");
        TEST_ASSERT_EQ(90, fetch_add_counter, &result, "counter should be 90");

        old = atomic_fetch_add(&fetch_add_counter, -50);
        TEST_ASSERT_EQ(90, old, &result, "fetch_add(-50) should return 90");
        TEST_ASSERT_EQ(40, fetch_add_counter, &result, "counter should be 40");

        /* Test going negative */
        old = atomic_fetch_add(&fetch_add_counter, -100);
        TEST_ASSERT_EQ(40, old, &result, "fetch_add(-100) should return 40");
        TEST_ASSERT_EQ(-60, fetch_add_counter, &result, "counter should be -60");
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);
    return result;
}

test_result_t test_fetch_add_concurrent_100(int hart_id, int ncores)
{
    test_result_t result = { .name = "fetch_add_concurrent_100", .passed = 0, .failed = 0 };
    const int ITERATIONS = 100;

    /* Setup */
    if (hart_id == 0) {
        fetch_add_counter = 0;
        for (int i = 0; i < NCORES; i++) {
            fetch_add_results[i] = 0;
        }
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    /* Each core increments 100 times */
    int local_sum = 0;
    for (int i = 0; i < ITERATIONS; i++) {
        int old = atomic_fetch_add(&fetch_add_counter, 1);
        local_sum += old;
    }
    fetch_add_results[hart_id] = local_sum;

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    /* Verify */
    if (hart_id == 0) {
        int expected = ncores * ITERATIONS;
        TEST_ASSERT_EQ(expected, fetch_add_counter, &result,
            "counter should equal ncores*100");

        /* Verify that each old value was unique (sum of 0 to ncores*100-1) */
        int total_old_sum = 0;
        for (int i = 0; i < ncores; i++) {
            total_old_sum += fetch_add_results[i];
        }
        /* Sum of 0 to (n-1) = n*(n-1)/2 */
        int n = ncores * ITERATIONS;
        int expected_sum = n * (n - 1) / 2;
        TEST_ASSERT_EQ(expected_sum, total_old_sum, &result,
            "sum of old values should be n*(n-1)/2");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

test_result_t test_fetch_add_concurrent_1000(int hart_id, int ncores)
{
    test_result_t result = { .name = "fetch_add_concurrent_1000", .passed = 0, .failed = 0 };
    const int ITERATIONS = 1000;

    /* Setup */
    if (hart_id == 0) {
        fetch_add_counter = 0;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    /* Each core increments 1000 times */
    for (int i = 0; i < ITERATIONS; i++) {
        atomic_fetch_add(&fetch_add_counter, 1);
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    /* Verify */
    if (hart_id == 0) {
        int expected = ncores * ITERATIONS;
        TEST_ASSERT_EQ(expected, fetch_add_counter, &result,
            "counter should equal ncores*1000");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

test_result_t test_fetch_add_concurrent_1000_with_random_nop(int hart_id, int ncores)
{
    test_result_t result = { .name = "fetch_add_concurrent_1000_with_random_nop", .passed = 0, .failed = 0 };
    const int ITERATIONS = 1000;

    /* Setup */
    if (hart_id == 0) {
        fetch_add_counter = 0;
        srand(42);
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    /* Each core increments 1000 times with random NOPs */
    for (int i = 0; i < ITERATIONS; i++) {
        atomic_fetch_add(&fetch_add_counter, 1);

        int nop_count = rand() % 100; // Random NOPs between 0-99
        for (int j = 0; j < nop_count; j++) {
            asm volatile ("nop");
        }
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    /* Verify */
    if (hart_id == 0) {
        int expected = ncores * ITERATIONS;
        TEST_ASSERT_EQ(expected, fetch_add_counter, &result,
            "counter should equal ncores*1000 with random NOPs");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}
