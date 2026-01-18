#include "test_common.h"

static volatile int sc_fail_var;
static volatile int sc_fail_ready[NCORES];
static volatile int sc_fail_results[NCORES];
static volatile int sc_intervene_var;
static volatile int sc_intervene_done;

static volatile int reservation_var1;
static volatile int reservation_var2;

test_result_t test_sc_fail_on_intervene(int hart_id, int ncores)
{
    test_result_t result = {.name = "sc_fail_on_intervene", .passed = 0, .failed = 0};

    if (ncores < 2) {
        // Need at least 2 cores for this test
        return result;
    }

    if (hart_id == 0) {
        sc_intervene_var = 100;
        sc_intervene_done = 0;
        for (int i = 0; i < ncores; i++) {
            sc_fail_ready[i] = 0;
            sc_fail_results[i] = -1;
        }
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    if (hart_id == 0) {
        int old_val, new_val, sc_result;

        // Do LR
        asm volatile("lr.w %[old], (%[ptr])"
                     : [old] "=r"(old_val)
                     : [ptr] "r"(&sc_intervene_var)
                     : "memory");

        // Signal that LR is done
        sc_fail_ready[0] = 1;

        // Wait for core 1 to intervene
        while (sc_intervene_done == 0) {}

        // Try SC - should fail because core 1 wrote to the address
        new_val = old_val + 1;
        asm volatile("sc.w %[ret], %[new], (%[ptr])"
                     : [ret] "=r"(sc_result)
                     : [new] "r"(new_val), [ptr] "r"(&sc_intervene_var)
                     : "memory");

        sc_fail_results[0] = sc_result;
    } else if (hart_id == 1) {
        // Wait for core 0 to do LR
        while (sc_fail_ready[0] == 0) {}

        // Write to the variable to invalidate core 0's reservation
        sc_intervene_var = 200;

        // Signal done
        sc_intervene_done = 1;
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);

    if (hart_id == 0) {
        // SC should have failed (returned non-zero)
        TEST_ASSERT(sc_fail_results[0] != 0, &result,
                    "SC should fail when another core writes between LR and SC");

        // Variable should still have the value written by core 1
        TEST_ASSERT_EQ(200, sc_intervene_var, &result,
                       "variable should have intervening write value");
    }

    pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
    return result;
}

test_result_t test_sc_different_address(int hart_id, int ncores)
{
    test_result_t result = {.name = "sc_different_address", .passed = 0, .failed = 0};

    if (hart_id == 0) {
        reservation_var1 = 10;
        reservation_var2 = 20;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    if (hart_id == 0) {
        int old_val, sc_result;

        // LR on var1
        asm volatile("lr.w %[old], (%[ptr])"
                     : [old] "=r"(old_val)
                     : [ptr] "r"(&reservation_var1)
                     : "memory");

        // Try SC on var2 (different address) - should fail
        int new_val = 99;
        asm volatile("sc.w %[ret], %[new], (%[ptr])"
                     : [ret] "=r"(sc_result)
                     : [new] "r"(new_val), [ptr] "r"(&reservation_var2)
                     : "memory");

        TEST_ASSERT(sc_result != 0, &result, "SC to different address than LR should fail");

        // var2 should be unchanged
        TEST_ASSERT_EQ(20, reservation_var2, &result, "var2 should be unchanged after failed SC");

        // Now do proper LR/SC on var1
        asm volatile("lr.w %[old], (%[ptr])"
                     : [old] "=r"(old_val)
                     : [ptr] "r"(&reservation_var1)
                     : "memory");

        new_val = 55;
        asm volatile("sc.w %[ret], %[new], (%[ptr])"
                     : [ret] "=r"(sc_result)
                     : [new] "r"(new_val), [ptr] "r"(&reservation_var1)
                     : "memory");

        TEST_ASSERT_EQ(0, sc_result, &result, "SC to same address as LR should succeed");
        TEST_ASSERT_EQ(55, reservation_var1, &result, "var1 should be updated after successful SC");
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);
    return result;
}

test_result_t test_reservation_overwrite(int hart_id, int ncores)
{
    test_result_t result = {.name = "reservation_overwrite", .passed = 0, .failed = 0};

    if (hart_id == 0) {
        reservation_var1 = 100;
        reservation_var2 = 200;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    if (hart_id == 0) {
        int old_val1, old_val2, sc_result;

        // LR on var1
        asm volatile("lr.w %[old], (%[ptr])"
                     : [old] "=r"(old_val1)
                     : [ptr] "r"(&reservation_var1)
                     : "memory");

        // LR on var2 (should overwrite reservation for var1)
        asm volatile("lr.w %[old], (%[ptr])"
                     : [old] "=r"(old_val2)
                     : [ptr] "r"(&reservation_var2)
                     : "memory");

        // SC on var1 should fail (reservation was overwritten)
        int new_val = 111;
        asm volatile("sc.w %[ret], %[new], (%[ptr])"
                     : [ret] "=r"(sc_result)
                     : [new] "r"(new_val), [ptr] "r"(&reservation_var1)
                     : "memory");

        TEST_ASSERT(sc_result != 0, &result, "SC on first LR address should fail after second LR");
        TEST_ASSERT_EQ(100, reservation_var1, &result, "var1 should be unchanged");

        // SC on var2 should succeed (current reservation)
        new_val = 222;
        asm volatile("sc.w %[ret], %[new], (%[ptr])"
                     : [ret] "=r"(sc_result)
                     : [new] "r"(new_val), [ptr] "r"(&reservation_var2)
                     : "memory");

        TEST_ASSERT_EQ(0, sc_result, &result, "SC on second LR address should succeed");
        TEST_ASSERT_EQ(222, reservation_var2, &result, "var2 should be updated");
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);
    return result;
}

test_result_t test_sc_without_lr(int hart_id, int ncores)
{
    test_result_t result = {.name = "sc_without_lr", .passed = 0, .failed = 0};

    if (hart_id == 0) {
        sc_fail_var = 123;
    }
    pg_barrier_at(BARRIER_TEST_SETUP, ncores);

    if (hart_id == 0) {
        int sc_result;

        // Do a successful LR/SC first to clear any previous state
        int dummy;
        asm volatile("lr.w %[old], (%[ptr])\n"
                     "sc.w %[ret], %[old], (%[ptr])"
                     : [ret] "=r"(sc_result), [old] "=r"(dummy)
                     : [ptr] "r"(&sc_fail_var)
                     : "memory");

        // Try SC without LR - should fail
        asm volatile("sc.w %[ret], %[new], (%[ptr])"
                     : [ret] "=r"(sc_result)
                     : [new] "r"(999), [ptr] "r"(&sc_fail_var)
                     : "memory");

        TEST_ASSERT(sc_result != 0, &result, "SC without LR should fail");
    }

    pg_barrier_at(BARRIER_TEST_RUN, ncores);
    return result;
}

static volatile int aqrl_test_var;
static volatile int aqrl_test_results[NCORES];

static inline int do_lr_none(volatile int *ptr)
{
    int val;
    asm volatile("lr.w %[v], (%[p])" : [v] "=r"(val) : [p] "r"(ptr) : "memory");
    return val;
}

static inline int do_lr_aq(volatile int *ptr)
{
    int val;
    asm volatile("lr.w.aq %[v], (%[p])" : [v] "=r"(val) : [p] "r"(ptr) : "memory");
    return val;
}

static inline int do_lr_rl(volatile int *ptr)
{
    int val;
    asm volatile("lr.w.rl %[v], (%[p])" : [v] "=r"(val) : [p] "r"(ptr) : "memory");
    return val;
}

static inline int do_lr_aqrl(volatile int *ptr)
{
    int val;
    asm volatile("lr.w.aqrl %[v], (%[p])" : [v] "=r"(val) : [p] "r"(ptr) : "memory");
    return val;
}

static inline int do_sc_none(volatile int *ptr, int val)
{
    int ret;
    asm volatile("sc.w %[r], %[v], (%[p])" : [r] "=r"(ret) : [v] "r"(val), [p] "r"(ptr) : "memory");
    return ret;
}

static inline int do_sc_aq(volatile int *ptr, int val)
{
    int ret;
    asm volatile("sc.w.aq %[r], %[v], (%[p])"
                 : [r] "=r"(ret)
                 : [v] "r"(val), [p] "r"(ptr)
                 : "memory");
    return ret;
}

static inline int do_sc_rl(volatile int *ptr, int val)
{
    int ret;
    asm volatile("sc.w.rl %[r], %[v], (%[p])"
                 : [r] "=r"(ret)
                 : [v] "r"(val), [p] "r"(ptr)
                 : "memory");
    return ret;
}

static inline int do_sc_aqrl(volatile int *ptr, int val)
{
    int ret;
    asm volatile("sc.w.aqrl %[r], %[v], (%[p])"
                 : [r] "=r"(ret)
                 : [v] "r"(val), [p] "r"(ptr)
                 : "memory");
    return ret;
}

/* Function pointer types */
typedef int (*lr_func_t)(volatile int *);
typedef int (*sc_func_t)(volatile int *, int);

static const lr_func_t lr_funcs[] = {do_lr_none, do_lr_aq, do_lr_rl, do_lr_aqrl};
static const sc_func_t sc_funcs[] = {do_sc_none, do_sc_aq, do_sc_rl, do_sc_aqrl};
static const char *lr_names[] = {"lr.w", "lr.w.aq", "lr.w.rl", "lr.w.aqrl"};
static const char *sc_names[] = {"sc.w", "sc.w.aq", "sc.w.rl", "sc.w.aqrl"};

test_result_t test_lr_sc_aqrl_variants(int hart_id, int ncores)
{
    test_result_t result = {.name = "lr_sc_aqrl_variants", .passed = 0, .failed = 0};
    const int ITERATIONS = 100;

    /* Test all 16 combinations: 4 LR variants x 4 SC variants */
    for (int lr_idx = 0; lr_idx < 4; lr_idx++) {
        for (int sc_idx = 0; sc_idx < 4; sc_idx++) {
            lr_func_t lr_func = lr_funcs[lr_idx];
            sc_func_t sc_func = sc_funcs[sc_idx];

            if (hart_id == 0) {
                aqrl_test_var = 0;
                for (int i = 0; i < ncores; i++) {
                    aqrl_test_results[i] = 0;
                }
            }
            pg_barrier_at(BARRIER_TEST_SETUP, ncores);

            int my_count = 0;
            for (int i = 0; i < ITERATIONS; i++) {
                int success = 0;
                while (!success) {
                    int old_val = lr_func(&aqrl_test_var);
                    int new_val = old_val + 1;
                    int sc_ret = sc_func(&aqrl_test_var, new_val);
                    if (sc_ret == 0) {
                        success = 1;
                        my_count++;
                    }
                }
            }
            aqrl_test_results[hart_id] = my_count;

            pg_barrier_at(BARRIER_TEST_RUN, ncores);

            if (hart_id == 0) {
                int expected = ncores * ITERATIONS;
                int total_count = 0;
                for (int i = 0; i < ncores; i++) {
                    total_count += aqrl_test_results[i];
                }

                TEST_ASSERT_EQ(expected, aqrl_test_var, &result,
                               "Final aqrl_test_var value mismatch");
                TEST_ASSERT_EQ(expected, total_count, &result, "Total count mismatch");
            }

            pg_barrier_at(BARRIER_TEST_VERIFY, ncores);
        }
    }

    return result;
}
