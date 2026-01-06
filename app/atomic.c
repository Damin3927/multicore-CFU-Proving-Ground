#include "atomic.h"
#include "util.h"

#ifndef NCORES
#define NCORES 4
#endif

static const int pg_barrier_default = PG_MAX_BARRIERS - 1;

static volatile int barrier_count[PG_MAX_BARRIERS];
static volatile int barrier_phase[PG_MAX_BARRIERS];

static inline int valid_hart(int hart_id) {
    return hart_id >= 0 && hart_id < NCORES;
}

static inline int valid_barrier(int barrier_id) {
    return barrier_id >= 0 && barrier_id < PG_MAX_BARRIERS;
}

void inline spinlock_acquire(volatile spinlock_t *lock) {
    while (atomic_exchange(lock, 1) != 0) {}
}

void inline spinlock_release(volatile spinlock_t *lock) {
    *lock = 0;
}

int atomic_fetch_add(volatile int *ptr, int val) {
    int old_val, new_val, ret;
    do {
        asm volatile (
            "lr.w %[old_val], (%[ptr])\n"
            "add %[new_val], %[old_val], %[val]\n"
            "sc.w %[ret], %[new_val], (%[ptr])\n"
            : [ret] "=&r" (ret), [old_val] "=&r" (old_val), [new_val] "=&r" (new_val)
            : [ptr] "r" (ptr), [val] "r" (val)
            : "memory"
        );
    } while (ret != 0);

    return old_val;
}

int atomic_exchange(volatile int *ptr, int val) {
    int old_val, ret;
    do {
        asm volatile (
            "lr.w %[old_val], (%[ptr])\n"
            "sc.w %[ret], %[val], (%[ptr])\n"
            : [ret] "=&r" (ret), [old_val] "=&r" (old_val)
            : [ptr] "r" (ptr), [val] "r" (val)
            : "memory"
        );
    } while (ret != 0);

    return old_val;
}

void pg_barrier_at(int barrier_id, int ncores) {
    if (!valid_barrier(barrier_id)) {
        return;
    }

    int phase = barrier_phase[barrier_id];
    int count = atomic_fetch_add(&barrier_count[barrier_id], 1) + 1;

    if (count == ncores) { // last core to arrive
        barrier_count[barrier_id] = 0;
        atomic_fetch_add(&barrier_phase[barrier_id], 1);
    } else { // wait for phase change
        while (barrier_phase[barrier_id] == phase) {}
    }
}

void pg_barrier(void) {
    pg_barrier_at(pg_barrier_default, NCORES);
}
