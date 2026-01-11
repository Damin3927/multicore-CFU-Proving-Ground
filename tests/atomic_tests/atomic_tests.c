#include "atomic.h"
#include "suites/test_common.h"
#include "util.h"

#ifndef NCORES
#define NCORES 4 // number of cores
#endif

typedef struct {
    const char *suite_name;
    test_func_t func;
} test_entry_t;

static const test_entry_t all_tests[] = {
    /* Fetch Add Tests */
    {"fetch_add_basic", test_fetch_add_basic},
    {"fetch_add_negative", test_fetch_add_negative},
    {"fetch_add_100", test_fetch_add_100},
    {"fetch_add_1000", test_fetch_add_1000},
    {"fetch_add_1000_with_random_nop", test_fetch_add_1000_random_nop},

    /* Exchange Tests */
    {"exchange_basic", test_exchange_basic},
    {"exchange_concurrent", test_exchange_concurrent},
    {"exchange_concurrent_50", test_exchange_concurrent_50},

    /* Barrier Tests */
    {"barrier_simple", test_barrier_simple},
    {"barrier_multiple", test_barrier_multiple},

    /* Other Tests */
    {"mixed_atomic_ops", test_mixed_atomic_ops},
    {"producer_consumer", test_producer_consumer},
    {"spinlock_basic", test_spinlock},
    {"cas_single", test_cas_single},
    {"cas_retry", test_cas_retry},
};

#define NUM_TESTS (sizeof(all_tests) / sizeof(all_tests[0]))

// Global test statistics
static volatile int total_passed;
static volatile int total_failed;
static volatile int tests_run;

void run_test(test_func_t test_func, const char *name, int hart_id, int ncores)
{
    if (hart_id == 0) {
        pg_prints("[TEST] ");
        pg_prints(name);
        pg_prints("\n");
    }

    pg_barrier();

    test_result_t result = test_func(hart_id, ncores);

    pg_barrier();

    if (hart_id == 0) {
        if (result.failed > 0) {
            pg_prints("  RESULT: FAILED (");
            pg_printd(result.passed);
            pg_prints(" passed, ");
            pg_printd(result.failed);
            pg_prints(" failed)\n");
            total_failed++;
        } else if (result.passed > 0) {
            pg_prints("  RESULT: PASSED (");
            pg_printd(result.passed);
            pg_prints(" checks)\n");
            total_passed++;
        } else {
            pg_prints("  RESULT: SKIPPED\n");
        }
        tests_run++;
    }
}

void print_header()
{
    pg_prints("\n");
    pg_prints("========================================\n");
    pg_prints("   RISC-V Atomic Operations Test Suite  \n");
    pg_prints("========================================\n");
    pg_prints("Number of cores: ");
    pg_printd(NCORES);
    pg_prints("\n");
    pg_prints("Number of tests: ");
    pg_printd(NUM_TESTS);
    pg_prints("\n");
    pg_prints("----------------------------------------\n\n");
}

void print_summary()
{
    pg_prints("\n");
    pg_prints("========================================\n");
    pg_prints("            TEST SUMMARY                \n");
    pg_prints("========================================\n");
    pg_prints("Tests run:    ");
    pg_printd(tests_run);
    pg_prints("\n");
    pg_prints("Tests passed: ");
    pg_printd(total_passed);
    pg_prints("\n");
    pg_prints("Tests failed: ");
    pg_printd(total_failed);
    pg_prints("\n");
    pg_prints("----------------------------------------\n");
    if (total_failed == 0) {
        pg_prints("ALL TESTS PASSED!\n");
    } else {
        pg_prints("SOME TESTS FAILED!\n");
    }
    pg_prints("========================================\n\n");
}

int main(void)
{
    int hart_id = pg_hart_id();

    if (hart_id == 0) {
        total_passed = 0;
        total_failed = 0;
        tests_run = 0;

        print_header();
    }

    pg_barrier();

    for (int i = 0; i < (int) NUM_TESTS; i++) {
        run_test(all_tests[i].func, all_tests[i].suite_name, hart_id, NCORES);
    }

    if (hart_id == 0) {
        print_summary();
    }

    pg_barrier();

    return 0;
}
