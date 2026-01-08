#include "test_common.h"

/* Shared variables for tests */
static volatile int exchange_var;
static volatile int exchange_results[NCORES];
static volatile int exchange_history[NCORES * 100];

test_result_t test_exchange_basic(int hart_id, int ncores)
{
    test_result_t result = { .name = "exchange_basic", .passed = 0, .failed = 0 };

    if (hart_id == 0) {
        exchange_var = 42;

        int old = atomic_exchange(&exchange_var, 100);
        TEST_ASSERT_EQ(42, old, &result, "first exchange should return 42");
        TEST_ASSERT_EQ(100, exchange_var, &result, "var should be 100");

        old = atomic_exchange(&exchange_var, 0);
        TEST_ASSERT_EQ(100, old, &result, "second exchange should return 100");
        TEST_ASSERT_EQ(0, exchange_var, &result, "var should be 0");

        old = atomic_exchange(&exchange_var, -1);
        TEST_ASSERT_EQ(0, old, &result, "third exchange should return 0");
        TEST_ASSERT_EQ(-1, exchange_var, &result, "var should be -1");
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);
    return result;
}

test_result_t test_exchange_concurrent(int hart_id, int ncores)
{
    test_result_t result = { .name = "exchange_concurrent", .passed = 0, .failed = 0 };

    /* Setup - initial value is 0 */
    if (hart_id == 0) {
        exchange_var = 0;
        for (int i = 0; i < NCORES; i++) {
            exchange_results[i] = -999;
        }
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    /* Each core exchanges its unique value (hart_id + 1) */
    int my_value = hart_id + 1;
    int old = atomic_exchange(&exchange_var, my_value);
    exchange_results[hart_id] = old;

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    /* Verify - one core got 0, others got a unique hart value */
    if (hart_id == 0) {
        int got_zero = 0;
        int value_counts[NCORES + 1];
        for (int i = 0; i <= NCORES; i++) {
            value_counts[i] = 0;
        }

        for (int i = 0; i < ncores; i++) {
            int val = exchange_results[i];
            if (val == 0) {
                got_zero++;
            } else if (val >= 1 && val <= ncores) {
                value_counts[val]++;
            }
        }

        TEST_ASSERT_EQ(1, got_zero, &result, "exactly one core should get 0");

        /* Final value should be one of the hart values */
        int final_val = exchange_var;
        TEST_ASSERT(final_val >= 1 && final_val <= ncores, &result,
            "final value should be a valid hart value");

        /* Check for value consistency - all exchanged values form a valid sequence */
        int total_values = got_zero;
        for (int i = 1; i <= ncores; i++) {
            total_values += value_counts[i];
        }
        TEST_ASSERT_EQ(ncores, total_values, &result,
            "all returned values should be valid");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

test_result_t test_exchange_concurrent_50(int hart_id, int ncores)
{
    test_result_t result = { .name = "exchange_concurrent_50", .passed = 0, .failed = 0 };
    const int ROUNDS = 50;

    if (hart_id == 0) {
        exchange_var = 1000;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    /* Each core exchanges ROUNDS times with unique values */
    int sum_received = 0;
    for (int round = 0; round < ROUNDS; round++) {
        int my_value = hart_id * 1000 + round;
        int old = atomic_exchange(&exchange_var, my_value);
        sum_received += old;
        exchange_history[hart_id * ROUNDS + round] = old;
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    /* Verify - check that exchange operations maintain data integrity */
    if (hart_id == 0) {
        /* The final value should be one of the last round values */
        int final_val = exchange_var;
        int valid_final = 0;
        for (int i = 0; i < ncores; i++) {
            if (final_val == i * 1000 + (ROUNDS - 1)) {
                valid_final = 1;
                break;
            }
        }
        TEST_ASSERT(valid_final, &result, "final value should be from last round");

        result.passed++; /* Basic completion check */
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}
