#define PG_MAX_BARRIERS 8

typedef volatile int spinlock_t;

void spinlock_acquire(volatile spinlock_t *lock);
void spinlock_release(volatile spinlock_t *lock);
int atomic_fetch_add(volatile int *ptr, int val);
int atomic_exchange(volatile int *ptr, int val);
void pg_barrier_at(int barrier_id, int ncores);
void pg_barrier(void);
