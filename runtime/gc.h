
#ifndef GC_H
#define GC_H

#include <stdint.h>

#define ALLOCS_START_SIZE 64

typedef struct {
    void* ptr;
    uint64_t size;
} Allocation;

// NOTE: If you add any fields to this struct, remember to fix the allocation
// size and initialization of this struct in the callFunc*.asm files, under
// callFunc()

typedef struct {
    // List of all allocations made by the GC
    Allocation* allocs;
    // Length of the allocations list
    uint64_t allocs_len;
    // Size of the allocations list (total size allocated for array)
    uint64_t allocs_end;
    // Reserved
    void* reserved_1;
    // This is the value of the total amount of alloc'd memory that the GC was
    // in charge of immediately _after_ the last collection
    uint64_t last_collection;
    // Total amount of memory currently allocated by GC. Running total,
    // incremented when allocations are made and decremented when freed
    uint64_t total_allocated;
} GC_Env;

typedef void (*Marking_Func_Ptr)(void* ptr);

void __GC_mellow_add_alloc(void* ptr, uint64_t size, GC_Env* gc_env);
void* __GC_malloc(uint64_t alloc_size, GC_Env* gc_env);
void* __GC_malloc_nocollect(uint64_t size, GC_Env* gc_env);
void __GC_mellow_mark_stack(void** rsp, void** stack_bot, GC_Env* gc_env);
uint64_t __GC_mellow_is_valid_ptr(void* ptr, GC_Env* gc_env);
void __GC_free_all_allocs(GC_Env* gc_env);
void __GC_sweep(GC_Env* gc_env);
void __GC_clear_marks(GC_Env* gc_env);

void __mellow_GC_mark_string(void* ptr);

#endif
