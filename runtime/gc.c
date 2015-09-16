
#include <stdint.h>
#include <stdlib.h>
#include "gc.h"

void* __GC_malloc(uint64_t alloc_size, GC_Env* gc_env)
{
    void* alloc = malloc(alloc_size);
    add_alloc(alloc, gc_env);
    return alloc;
}

void add_alloc(void* alloc, GC_Env* gc_env)
{
    if (gc_env->allocs == NULL)
    {
        uint64_t start_size = ALLOCS_START_SIZE;
        void** allocs = malloc(start_size);
        if (allocs == NULL)
        {
            // Error case
        }
        gc_env->allocs = allocs;
        gc_env->allocs_len = 0;
        gc_env->allocs_end = start_size;
    }
    else if (gc_env->allocs_len >= gc_env->allocs_end)
    {
        uint64_t new_size = gc_env->allocs_end * 2;
        void** new_allocs = realloc(gc_env->allocs, new_size);
        if (new_allocs == NULL)
        {
            // Error case
        }
        gc_env->allocs = new_allocs;
        gc_env->allocs_end = new_size;
    }
    gc_env->allocs[gc_env->allocs_len] = alloc;
    gc_env->allocs_len += 1;
}

void __GC_free_all_allocs(GC_Env* gc_env)
{
    uint64_t i;
    for (i = 0; i < gc_env->allocs_len; i++)
    {
        free(gc_env->allocs[i]);
    }
    free(gc_env->allocs);
    gc_env->allocs = NULL;
    gc_env->allocs_len = 0;
    gc_env->allocs_end = 0;
}

inline uint64_t is_marked(void* ptr)
{
    // The leftmost bit of the allocated memory is the 'mark' bit. The object
    // header is 16 bytes:
    // [1 bit 'mark'][7+3*8 'util'][4 bytes 'type'][8 bytes 'util']
    if (((uint8_t*)ptr)[0] & 0b10000000 != 0)
    {
        return 1;
    }
    return 0;
}

void __GC_sweep(GC_Env* gc_env)
{
    uint64_t i = 0;
    uint64_t j = gc_env->allocs_len - 1;
    // Move through the allocs array and free everything that needs to be
    // free'd, while keeping the list of valid ptrs contiguous and left-
    // justified. At the end of this loop, both i and j should be equal, and
    // they will represent one-less than the new gc_env->allocs_len value. This
    // algorithm is O(n), as the list of allocs need not be sorted
    for (; i < j; i++)
    {
        if (__GC_is_marked(gc_env->allocs[i]) == 0)
        {
            // Free the unmarked ptr
            free(gc_env->allocs[i]);
            // While rightmost ptr is unmarked, move left in search of a marked
            // ptr, free'ing along the way
            for (; j > i && __GC_is_marked(gc_env->allocs[j] == 0); j--)
            {
                free(gc_env->allocs[j]);
            }
            // All ptrs from i to gc_env->allocs_len were free'd, so we're done
            if (j == i)
            {
                break;
            }
            // We found a ptr we can slot into the free spot i found, so
            // make the move, decrement our "end" counter j, and loop
            else
            {
                gc_env->allocs[i] = gc_env->allocs[j];
                j--;
            }
        }
    }
    // After this algorithm: gc_env->allocs_len == i + 1 == j + 1
    gc_env->allocs_len = i + 1;
}
