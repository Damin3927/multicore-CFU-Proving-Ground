#include "test_common.h"

/* Shared variables for tests */
static volatile int mixed_counter1;
static volatile int mixed_counter2;
static volatile int mixed_flag;
static volatile int producer_data[100];
static volatile int producer_idx;
static volatile int consumer_idx;
static volatile int consumer_sum;
static volatile int lock_var;
static volatile int critical_section_data;
static volatile int cs_results[NCORES];

test_result_t test_mixed_atomic_ops(int hart_id, int ncores)
{
    test_result_t result = { .name = "mixed_atomic_ops", .passed = 0, .failed = 0 };
    const int ITERATIONS = 50;

    if (hart_id == 0) {
        mixed_counter1 = 0;
        mixed_counter2 = 1000;
        mixed_flag = 0;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    for (int i = 0; i < ITERATIONS; i++) {
        /* Alternate between different operations based on iteration */
        if (i % 3 == 0) {
            atomic_fetch_add(&mixed_counter1, 1);
        } else if (i % 3 == 1) {
            atomic_add(&mixed_counter2, -1);
        } else {
            /* Exchange to toggle flag */
            atomic_exchange(&mixed_flag, hart_id);
        }
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    /* Verify */
    if (hart_id == 0) {
        /* counter1 should have received ~(ITERATIONS/3) per core */
        int expected_adds = ((ITERATIONS + 2) / 3) * ncores;
        TEST_ASSERT_EQ(expected_adds, mixed_counter1, &result,
            "counter1 should be correct");

        /* counter2 should have decreased by same amount */
        int expected_counter2 = 1000 - expected_adds;
        TEST_ASSERT_EQ(expected_counter2, mixed_counter2, &result,
            "counter2 should be correct");

        /* flag should be a valid hart_id */
        int valid_flag = (mixed_flag >= 0 && mixed_flag < ncores);
        TEST_ASSERT(valid_flag, &result, "flag should be valid hart_id");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

test_result_t test_producer_consumer(int hart_id, int ncores)
{
    test_result_t result = { .name = "producer_consumer", .passed = 0, .failed = 0 };
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
        /* Producer: write data and advance index */
        for (int i = 0; i < NUM_ITEMS; i++) {
            producer_data[i] = i + 1;
            atomic_fetch_add(&producer_idx, 1);
        }
    } else {
        /* Consumer: read data as it becomes available */
        int my_sum = 0;
        while (1) {
            int my_idx = atomic_fetch_add(&consumer_idx, 1);
            if (my_idx >= NUM_ITEMS) {
                break;
            }

            /* Wait for producer */
            while (producer_idx <= my_idx) {}

            my_sum += producer_data[my_idx];
        }
        atomic_fetch_add(&consumer_sum, my_sum);
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    /* Verify */
    if (hart_id == 0) {
        /* Expected sum: 1 + 2 + ... + NUM_ITEMS = NUM_ITEMS*(NUM_ITEMS+1)/2 */
        int expected_sum = NUM_ITEMS * (NUM_ITEMS + 1) / 2;
        TEST_ASSERT_EQ(expected_sum, consumer_sum, &result,
            "consumer sum should be correct");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

static inline void spinlock_lock(volatile int *lock)
{
    while (atomic_exchange(lock, 1) != 0) {}
}

static inline void spinlock_unlock(volatile int *lock)
{
    *lock = 0;
}

test_result_t test_spinlock_basic(int hart_id, int ncores)
{
    test_result_t result = { .name = "spinlock_basic", .passed = 0, .failed = 0 };

    if (hart_id == 0) {
        lock_var = 0;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    /* Each core tries to acquire and release lock */
    spinlock_lock(&lock_var);

    /* Inside critical section - lock should be 1 */
    int lock_val = lock_var;

    spinlock_unlock(&lock_var);

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    if (hart_id == 0) {
        /* After all unlocks, lock should be 0 */
        TEST_ASSERT_EQ(0, lock_var, &result, "lock should be 0 after all unlocks");
        result.passed++; /* Basic test passed */
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

test_result_t test_spinlock_critical_section(int hart_id, int ncores)
{
    test_result_t result = { .name = "spinlock_critical_section", .passed = 0, .failed = 0 };
    const int ITERATIONS = 50;

    if (hart_id == 0) {
        lock_var = 0;
        critical_section_data = 0;
        for (int i = 0; i < NCORES; i++) {
            cs_results[i] = 0;
        }
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    /* Each core increments critical_section_data ITERATIONS times under lock */
    for (int i = 0; i < ITERATIONS; i++) {
        spinlock_lock(&lock_var);

        /* Critical section - read-modify-write without atomics */
        int old_val = critical_section_data;
        /* Small delay to increase chance of race if lock doesn't work */
        volatile int delay = 0;
        for (int d = 0; d < 10; d++) {
            delay += d;
        }
        critical_section_data = old_val + 1;

        spinlock_unlock(&lock_var);
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    /* Verify */
    if (hart_id == 0) {
        int expected = ncores * ITERATIONS;
        TEST_ASSERT_EQ(expected, critical_section_data, &result,
            "critical section counter should be ncores*ITERATIONS");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

static volatile int cas_var;
static volatile int cas_success[NCORES];

static int compare_and_swap(volatile int *ptr, int expected, int new_val)
{
    int old_val, sc_result;

    asm volatile (
        "lr.w %[old], (%[ptr])\n"
        : [old] "=r" (old_val)
        : [ptr] "r" (ptr)
        : "memory"
    );

    if (old_val != expected) {
        return 0; /* Failed - value was not as expected */
    }

    asm volatile (
        "sc.w %[ret], %[new], (%[ptr])\n"
        : [ret] "=r" (sc_result)
        : [new] "r" (new_val), [ptr] "r" (ptr)
        : "memory"
    );

    return (sc_result == 0); /* Success if sc succeeded */
}

test_result_t test_compare_and_swap(int hart_id, int ncores)
{
    test_result_t result = { .name = "compare_and_swap", .passed = 0, .failed = 0 };

    if (hart_id == 0) {
        cas_var = 0;
        for (int i = 0; i < NCORES; i++) {
            cas_success[i] = 0;
        }
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    /* All cores try to CAS from 0 to their hart_id+1 */
    int success = compare_and_swap(&cas_var, 0, hart_id + 1);
    cas_success[hart_id] = success;

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    /* Verify */
    if (hart_id == 0) {
        /* Exactly one core should have succeeded */
        int success_count = 0;
        int winning_hart = -1;
        for (int i = 0; i < ncores; i++) {
            if (cas_success[i]) {
                success_count++;
                winning_hart = i;
            }
        }
        TEST_ASSERT_EQ(1, success_count, &result,
            "exactly one CAS should succeed");

        /* The value should match the winning hart */
        if (winning_hart >= 0) {
            TEST_ASSERT_EQ(winning_hart + 1, cas_var, &result,
                "value should match winning hart");
        }
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}
