void atomic_add(volatile int *ptr, int val) {
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
}
