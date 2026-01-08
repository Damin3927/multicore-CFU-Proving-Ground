#include "test_common.h"

/* Shared variables for tests */
static volatile int barrier_phase_tracker[NCORES];
static volatile int barrier_order[NCORES * 100];
static volatile int barrier_order_idx;
static volatile int barrier_counter;

test_result_t test_barrier_simple(int hart_id, int ncores)
{
    test_result_t result = { .name = "barrier_simple", .passed = 0, .failed = 0 };

    /* Setup */
    if (hart_id == 0) {
        for (int i = 0; i < NCORES; i++) {
            barrier_phase_tracker[i] = 0;
        }
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    /* Phase 1: Set flag before barrier */
    barrier_phase_tracker[hart_id] = 1;

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    /* After barrier, all flags should be 1 */
    int all_set = 1;
    for (int i = 0; i < ncores; i++) {
        if (barrier_phase_tracker[i] != 1) {
            all_set = 0;
        }
    }

    if (hart_id == 0) {
        TEST_ASSERT(all_set, &result, "all cores should have phase=1 after barrier");
    }

    /* Phase 2: Set flag to 2 */
    barrier_phase_tracker[hart_id] = 2;

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);

    /* After second barrier, all should be 2 */
    all_set = 1;
    for (int i = 0; i < ncores; i++) {
        if (barrier_phase_tracker[i] != 2) {
            all_set = 0;
        }
    }

    if (hart_id == 0) {
        TEST_ASSERT(all_set, &result, "all cores should have phase=2 after barrier");
    }

    pg_barrier_at(BARRIER_TEST_CLEANUP, ncores);
    return result;
}

test_result_t test_barrier_multiple(int hart_id, int ncores)
{
    test_result_t result = { .name = "barrier_multiple", .passed = 0, .failed = 0 };
    const int NUM_BARRIERS = 20;

    if (hart_id == 0) {
        barrier_counter = 0;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    for (int i = 0; i < NUM_BARRIERS; i++) {
        /* Each core increments counter */
        atomic_fetch_add(&barrier_counter, 1);

        pg_barrier_at(BARRIER_TEST_RUN, ncores);

        /* After barrier, counter should be (i+1) * ncores */
        int expected = (i + 1) * ncores;
        if (hart_id == 0 && i == NUM_BARRIERS - 1) {
            TEST_ASSERT_EQ(expected, barrier_counter, &result,
                "counter should be NUM_BARRIERS * ncores");
        }
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}
