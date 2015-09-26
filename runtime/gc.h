
#ifndef GC_H
#define GC_H

#include <stdint.h>

#define ALLOCS_START_SIZE 64

typedef struct {
    void** allocs;
    uint64_t allocs_len;
    uint64_t allocs_end;
} GC_Env;

void* __GC_malloc(uint64_t alloc_size, GC_Env* gc_env);
void __GC_track(void* ptr, GC_Env* gc_env);
void __GC_free_all_allocs(GC_Env* gc_env);
void __GC_sweep(GC_Env* gc_env);
void __GC_clear_marks(GC_Env* gc_env);

#endif
