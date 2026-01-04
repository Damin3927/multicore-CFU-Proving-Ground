#include "test_common.h"

/* Shared variables for tests */
static volatile int lr_sc_var;
static volatile int lr_sc_retry_count[NCORES];
static volatile int contention_var;
static volatile int contention_success[NCORES];

static int atomic_fetch_add_with_retry_count(volatile int *ptr, int val, int *retry_count)
{
    int old_val, new_val, ret;
    *retry_count = 0;

    do {
        asm volatile (
            "lr.w %[old_val], (%[ptr])\n"
            "add %[new_val], %[old_val], %[val]\n"
            "sc.w %[ret], %[new_val], (%[ptr])\n"
            : [ret] "=&r" (ret), [old_val] "=&r" (old_val), [new_val] "=&r" (new_val)
            : [ptr] "r" (ptr), [val] "r" (val)
            : "memory"
        );
        if (ret != 0) {
            (*retry_count)++;
        }
    } while (ret != 0);

    return old_val;
}

test_result_t test_lr_sc_retry(int hart_id, int ncores)
{
    test_result_t result = { .name = "lr_sc_retry", .passed = 0, .failed = 0 };
    const int ITERATIONS = 50;

    if (hart_id == 0) {
        lr_sc_var = 0;
        for (int i = 0; i < NCORES; i++) {
            lr_sc_retry_count[i] = 0;
        }
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    /* All cores compete for the same variable */
    int total_retries = 0;
    for (int i = 0; i < ITERATIONS; i++) {
        int retries;
        atomic_fetch_add_with_retry_count(&lr_sc_var, 1, &retries);
        total_retries += retries;
    }
    lr_sc_retry_count[hart_id] = total_retries;

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    /* Verify */
    if (hart_id == 0) {
        /* Counter should be correct despite retries */
        int expected = ncores * ITERATIONS;
        TEST_ASSERT_EQ(expected, lr_sc_var, &result,
            "counter should be correct despite retries");

        /* In multicore, some retries should have occurred */
        int total_all_retries = 0;
        for (int i = 0; i < ncores; i++) {
            total_all_retries += lr_sc_retry_count[i];
        }

        pg_prints("  Info: total LR/SC retries = ");
        pg_printd(total_all_retries);
        pg_prints("\n");

        /* With multiple cores, we expect some retries */
        if (ncores > 1) {
            TEST_ASSERT(total_all_retries > 0, &result,
                "multicore should have some retries");
        } else {
            result.passed++; /* Single core - no retries expected */
        }
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

test_result_t test_lr_sc_contention(int hart_id, int ncores)
{
    test_result_t result = { .name = "lr_sc_contention", .passed = 0, .failed = 0 };
    const int ITERATIONS = 200;

    if (hart_id == 0) {
        contention_var = 0;
        for (int i = 0; i < NCORES; i++) {
            contention_success[i] = 0;
        }
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    /* Rapid-fire atomic operations */
    int success_count = 0;
    for (int i = 0; i < ITERATIONS; i++) {
        int old = atomic_fetch_add(&contention_var, 1);
        if (old >= 0) { /* Basic sanity check */
            success_count++;
        }
    }
    contention_success[hart_id] = success_count;

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    /* Verify */
    if (hart_id == 0) {
        int expected = ncores * ITERATIONS;
        TEST_ASSERT_EQ(expected, contention_var, &result,
            "high contention counter should be correct");

        int total_success = 0;
        for (int i = 0; i < ncores; i++) {
            total_success += contention_success[i];
        }
        TEST_ASSERT_EQ(ncores * ITERATIONS, total_success, &result,
            "all operations should succeed");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

static volatile int raw_lr_sc_var;

test_result_t test_raw_lr_sc(int hart_id, int ncores)
{
    test_result_t result = { .name = "raw_lr_sc", .passed = 0, .failed = 0 };

    if (hart_id == 0) {
        raw_lr_sc_var = 0;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    /* Each core performs raw LR/SC compare-and-swap like operation */
    int old_val, new_val, sc_result;

    /* Try to set var to (hart_id + 1) * 10 if it's 0 */
    do {
        asm volatile (
            "lr.w %[old], (%[ptr])\n"
            : [old] "=r" (old_val)
            : [ptr] "r" (&raw_lr_sc_var)
            : "memory"
        );

        /* Only try to change if still 0 */
        if (old_val != 0) {
            break;
        }

        new_val = (hart_id + 1) * 10;

        asm volatile (
            "sc.w %[ret], %[new], (%[ptr])\n"
            : [ret] "=r" (sc_result)
            : [new] "r" (new_val), [ptr] "r" (&raw_lr_sc_var)
            : "memory"
        );
    } while (sc_result != 0);

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    /* Verify - exactly one core should have succeeded */
    if (hart_id == 0) {
        int val = raw_lr_sc_var;
        int valid = 0;
        for (int i = 0; i < ncores; i++) {
            if (val == (i + 1) * 10) {
                valid = 1;
                break;
            }
        }
        TEST_ASSERT(valid, &result, "exactly one core should have set the value");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}
