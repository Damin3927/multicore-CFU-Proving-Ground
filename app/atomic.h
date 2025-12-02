#ifndef PG_MAX_BARRIERS
#define PG_MAX_BARRIERS 8
#endif

#define PG_BARRIER_DEFAULT 0

typedef volatile int spinlock_t;

int atomic_fetch_add(volatile int *ptr, int val);
void atomic_add(volatile int *ptr, int val);
int atomic_exchange(volatile int *ptr, int val);
void pg_barrier_at(int barrier_id);
void pg_barrier(void);
