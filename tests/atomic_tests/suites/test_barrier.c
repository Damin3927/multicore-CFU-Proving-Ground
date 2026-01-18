#include "test_common.h"

static volatile int arrival_count;
static volatile int shared_counter;

static void do_work(int iterations)
{
    volatile int sum = 0;
    for (int i = 0; i < iterations; i++) {
        sum += i;
    }
}
test_result_t test_barrier_atomic_counter(int hart_id, int ncores)
{
    test_result_t result = {.name = "barrier_atomic_counter", .passed = 0, .failed = 0};

    if (hart_id == 0) {
        arrival_count = 0;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    atomic_fetch_add(&arrival_count, 1);

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    int count_after_barrier = arrival_count;

    TEST_ASSERT_EQ(ncores, count_after_barrier, &result,
                   "arrival_count should equal ncores after barrier");

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

test_result_t test_barrier_delay_injection(int hart_id, int ncores)
{
    test_result_t result = {.name = "barrier_delay_injection", .passed = 0, .failed = 0};

    if (hart_id == 0) {
        arrival_count = 0;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    if (hart_id == 0) {
        do_work(10000);
    }

    atomic_fetch_add(&arrival_count, 1);

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    int count_after_barrier = arrival_count;

    TEST_ASSERT_EQ(ncores, count_after_barrier, &result,
                   "slow core should have arrived before fast cores exit barrier");

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

test_result_t test_barrier_continuous(int hart_id, int ncores)
{
    test_result_t result = {.name = "barrier_continuous", .passed = 0, .failed = 0};
    const int NUM_ITERATIONS = 1000;

    if (hart_id == 0) {
        shared_counter = 0;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    int local_errors = 0;

    for (int round = 0; round < NUM_ITERATIONS; round++) {
        atomic_fetch_add(&shared_counter, 1);

        pg_barrier_at(BARRIER_TEST_RUN, ncores);

        int expected = (round + 1) * ncores;
        if (shared_counter != expected) {
            local_errors++;
        }

        pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    }

    if (hart_id == 0) {
        TEST_ASSERT_EQ(0, local_errors, &result, "counter should match expected at each round");
        TEST_ASSERT_EQ(NUM_ITERATIONS * ncores, shared_counter, &result,
                       "final counter should be NUM_ITERATIONS * ncores");
    }

    pg_barrier_at(BARRIER_TEST_CLEANUP, ncores);
    return result;
}
