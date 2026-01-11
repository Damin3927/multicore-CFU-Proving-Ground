#include "test_common.h"

static volatile int mixed_counter1;
static volatile int mixed_counter2;
static volatile int mixed_flag;
static volatile int producer_data[100];
static volatile int producer_idx;
static volatile int consumer_idx;
static volatile int consumer_sum;
static volatile int lock_var;
static volatile int critical_section_data;

test_result_t test_mixed_atomic_ops(int hart_id, int ncores)
{
    test_result_t result = {.name = "mixed_atomic_ops", .passed = 0, .failed = 0};
    const int ITERATIONS = 50;

    if (hart_id == 0) {
        mixed_counter1 = 0;
        mixed_counter2 = 1000;
        mixed_flag = 0;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    for (int i = 0; i < ITERATIONS; i++) {
        if (i % 3 == 0) {
            atomic_fetch_add(&mixed_counter1, 1);
        } else if (i % 3 == 1) {
            atomic_fetch_add(&mixed_counter2, -1);
        } else {
            atomic_exchange(&mixed_flag, hart_id);
        }
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    if (hart_id == 0) {
        int expected_adds = ((ITERATIONS + 2) / 3) * ncores;
        TEST_ASSERT_EQ(expected_adds, mixed_counter1, &result, "counter1 should be correct");

        int expected_counter2 = 1000 - expected_adds;
        TEST_ASSERT_EQ(expected_counter2, mixed_counter2, &result, "counter2 should be correct");

        int valid_flag = (mixed_flag >= 0 && mixed_flag < ncores);
        TEST_ASSERT(valid_flag, &result, "flag should be valid hart_id");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

test_result_t test_producer_consumer(int hart_id, int ncores)
{
    test_result_t result = {.name = "producer_consumer", .passed = 0, .failed = 0};
    const int NUM_ITEMS = 80;

    if (hart_id == 0) {
        for (int i = 0; i < 100; i++) {
            producer_data[i] = 0;
        }
        producer_idx = 0;
        consumer_idx = 0;
        consumer_sum = 0;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    if (hart_id == 0) {
        // Producer: write data items
        for (int i = 0; i < NUM_ITEMS; i++) {
            producer_data[i] = i + 1;
            atomic_fetch_add(&producer_idx, 1);
        }
    } else {
        // Consumers: read data items
        int my_sum = 0;
        while (1) {
            int my_idx = atomic_fetch_add(&consumer_idx, 1);
            if (my_idx >= NUM_ITEMS) {
                break;
            }

            // Wait for producer
            while (producer_idx <= my_idx) {}

            my_sum += producer_data[my_idx];
        }
        atomic_fetch_add(&consumer_sum, my_sum);
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    if (hart_id == 0) {
        int expected_sum = NUM_ITEMS * (NUM_ITEMS + 1) / 2;
        TEST_ASSERT_EQ(expected_sum, consumer_sum, &result, "consumer sum should be correct");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

test_result_t test_spinlock(int hart_id, int ncores)
{
    test_result_t result = {.name = "spinlock", .passed = 0, .failed = 0};
    const int ITERATIONS = 100;

    if (hart_id == 0) {
        lock_var = 0;
        critical_section_data = 0;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    for (int i = 0; i < ITERATIONS; i++) {
        spinlock_acquire(&lock_var);

        // non-atomic critical section
        int temp = critical_section_data;
        temp = temp + 1;
        critical_section_data = temp;

        spinlock_release(&lock_var);
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    if (hart_id == 0) {
        int expected = ncores * ITERATIONS;
        TEST_ASSERT_EQ(expected, critical_section_data, &result,
                       "counter should equal ncores * ITERATIONS");

        TEST_ASSERT_EQ(0, lock_var, &result, "lock should be 0 after all releases");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

static volatile int cas_var;
static volatile int cas_counter;
static volatile int cas_attempts[NCORES];
static volatile int cas_successes[NCORES];

static int compare_and_swap(volatile int *ptr, int expected, int new_val)
{
    int old_val, ret;

    asm volatile("lr.w %[old], (%[ptr])\n"
                 "bne %[old], %[exp], 1f\n" // If not expected, skip SC
                 "sc.w %[ret], %[new], (%[ptr])\n"
                 "j 2f\n"
                 "1: li %[ret], 1\n" // Set ret=1 to indicate failure
                 "2:\n"
                 : [ret] "=&r"(ret), [old] "=&r"(old_val)
                 : [ptr] "r"(ptr), [exp] "r"(expected), [new] "r"(new_val)
                 : "memory");

    return (ret == 0);
}

test_result_t test_cas_single(int hart_id, int ncores)
{
    test_result_t result = {.name = "cas_single", .passed = 0, .failed = 0};

    if (hart_id == 0) {
        cas_var = 0;
        for (int i = 0; i < NCORES; i++) {
            cas_successes[i] = 0;
        }
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    int success = compare_and_swap(&cas_var, 0, hart_id + 1);
    cas_successes[hart_id] = success;

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    if (hart_id == 0) {
        int success_count = 0;
        int winning_hart = -1;
        for (int i = 0; i < ncores; i++) {
            if (cas_successes[i]) {
                success_count++;
                winning_hart = i;
            }
        }
        TEST_ASSERT_EQ(1, success_count, &result, "exactly one CAS should succeed");

        if (winning_hart >= 0) {
            TEST_ASSERT_EQ(winning_hart + 1, cas_var, &result, "value should match winning hart");
        }
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

test_result_t test_cas_retry(int hart_id, int ncores)
{
    test_result_t result = {.name = "cas_retry", .passed = 0, .failed = 0};
    const int ITERATIONS = 50;

    if (hart_id == 0) {
        cas_counter = 0;
        for (int i = 0; i < NCORES; i++) {
            cas_attempts[i] = 0;
            cas_successes[i] = 0;
        }
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    for (int i = 0; i < ITERATIONS; i++) {
        int success = 0;
        while (!success) {
            int old_val = cas_counter;
            success = compare_and_swap(&cas_counter, old_val, old_val + 1);
            cas_attempts[hart_id]++;
            if (success) {
                cas_successes[hart_id]++;
            }
        }
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    if (hart_id == 0) {
        int expected_counter = ncores * ITERATIONS;
        TEST_ASSERT_EQ(expected_counter, cas_counter, &result,
                       "counter should equal ncores * ITERATIONS");

        int total_successes = 0;
        for (int i = 0; i < ncores; i++) {
            total_successes += cas_successes[i];
        }
        TEST_ASSERT_EQ(expected_counter, total_successes, &result,
                       "total successes should equal ncores * ITERATIONS");

        int total_attempts = 0;
        for (int i = 0; i < ncores; i++) {
            total_attempts += cas_attempts[i];
        }
        TEST_ASSERT(total_attempts >= total_successes, &result,
                    "total attempts should be >= total successes");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}
