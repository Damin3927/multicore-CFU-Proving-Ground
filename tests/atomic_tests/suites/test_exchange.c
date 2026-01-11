#include "test_common.h"

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

    if (hart_id == 0) {
        exchange_var = 0;
        for (int i = 0; i < NCORES; i++) {
            exchange_results[i] = -999;
        }
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    int my_value = hart_id + 1;
    int old = atomic_exchange(&exchange_var, my_value);
    exchange_results[hart_id] = old;

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    if (hart_id == 0) {
        int got_zero_idx = -1;
        int value_counts[NCORES];
        for (int i = 0; i < NCORES; i++) {
            value_counts[i] = 0;
        }

        for (int i = 0; i < ncores; i++) {
            int val = exchange_results[i];
            if (val == 0) {
                got_zero_idx = i;
            } else if (val >= 1 && val <= ncores) {
                value_counts[val - 1]++;
            } else {
                TEST_ASSERT(0, &result, "received value out of expected range");
            }
        }

        TEST_ASSERT(got_zero_idx != -1, &result, "one core should have received 0");

        int final_val = exchange_var;
        TEST_ASSERT(final_val >= 1 && final_val <= ncores, &result, "final value should be a valid hart value");

        for (int i = 0; i < ncores; i++) {
            int value = i + 1;
            int expected_count = (value == final_val) ? 0 : 1;
            TEST_ASSERT_EQ(expected_count, value_counts[i], &result, "each value should appear correct number of times");
        }
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

    if (hart_id == 0) {
        int final_val = exchange_var;

        long long expected_sum = 1000;
        for (int core = 0; core < ncores; core++) {
            for (int round = 0; round < ROUNDS; round++) {
                expected_sum += core * 1000 + round;
            }
        }

        long long actual_sum = final_val;
        for (int core = 0; core < ncores; core++) {
            for (int round = 0; round < ROUNDS; round++) {
                actual_sum += exchange_history[core * ROUNDS + round];
            }
        }

        TEST_ASSERT_EQ(expected_sum, actual_sum, &result, "sum of all values must be conserved");

        int expected_written[NCORES * ROUNDS + 1];
        int expected_count = 0;
        expected_written[expected_count++] = 1000;
        for (int core = 0; core < ncores; core++) {
            for (int round = 0; round < ROUNDS; round++) {
                expected_written[expected_count++] = core * 1000 + round;
            }
        }

        int actual_received[NCORES * ROUNDS + 1];
        int actual_count = 0;
        for (int core = 0; core < ncores; core++) {
            for (int round = 0; round < ROUNDS; round++) {
                actual_received[actual_count++] = exchange_history[core * ROUNDS + round];
            }
        }
        actual_received[actual_count++] = final_val;

        for (int i = 0; i < expected_count - 1; i++) {
            for (int j = i + 1; j < expected_count; j++) {
                if (expected_written[i] > expected_written[j]) {
                    int tmp = expected_written[i];
                    expected_written[i] = expected_written[j];
                    expected_written[j] = tmp;
                }
            }
        }
        for (int i = 0; i < actual_count - 1; i++) {
            for (int j = i + 1; j < actual_count; j++) {
                if (actual_received[i] > actual_received[j]) {
                    int tmp = actual_received[i];
                    actual_received[i] = actual_received[j];
                    actual_received[j] = tmp;
                }
            }
        }

        TEST_ASSERT_EQ(expected_count, actual_count, &result, "value count mismatch");
        for (int i = 0; i < expected_count; i++) {
            TEST_ASSERT_EQ(expected_written[i], actual_received[i], &result, "value sets must match exactly");
        }
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}
