
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include "gc.h"

void __GC_mellow_add_alloc(void* ptr, uint64_t size, GC_Env* gc_env)
{
    if (gc_env->allocs == NULL)
    {
        uint64_t start_size = ALLOCS_START_SIZE;
        Allocation* allocs = malloc(start_size * sizeof(Allocation));
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
        uint64_t new_size = (uint64_t)(gc_env->allocs_end * 1.5);
        Allocation* new_allocs = realloc(
            gc_env->allocs,
            new_size  * sizeof(Allocation)
        );
        if (new_allocs == NULL)
        {
            // Error case
        }
        gc_env->allocs = new_allocs;
        gc_env->allocs_end = new_size;
    }
    gc_env->allocs[gc_env->allocs_len].ptr = ptr;
    gc_env->allocs[gc_env->allocs_len].size = size;
    gc_env->allocs_len += 1;
    gc_env->total_allocated += size;
}

void* __GC_malloc_nocollect(uint64_t size, GC_Env* gc_env)
{
    void* ptr = calloc(size, 1);
    __GC_mellow_add_alloc(ptr, size, gc_env);
    return ptr;
}

void* __GC_malloc_wrapped(
    uint64_t size, GC_Env* gc_env, void** rsp, void** stack_bot
) {
    if (gc_env->total_allocated > gc_env->last_collection * 1.5)
    {
        __GC_mellow_mark_stack(rsp, stack_bot, gc_env);
        __GC_sweep(gc_env);
        __GC_clear_marks(gc_env);
        gc_env->last_collection = gc_env->total_allocated;
    }

    void* ptr = calloc(size, 1);
    __GC_mellow_add_alloc(ptr, size, gc_env);
    return ptr;
}

void __GC_mellow_mark_stack(void** rsp, void** stack_bot, GC_Env* gc_env)
{
    uint64_t index;
    uint64_t indices = ((uint64_t)stack_bot - (uint64_t)rsp) / 8;
    // Absolutely ensure we're 8-byte aligned
    if ((uint64_t)rsp % 8 != 0) {
        rsp = (void**)((uint64_t)rsp + (8 - ((uint64_t)rsp % 8)));
    }
    for (index = 0; index < indices; index++)
    {
        void* ptr = rsp[index];
        if (__GC_mellow_is_valid_ptr(ptr, gc_env))
        {
            Marking_Func_Ptr mark_func_ptr = ((Marking_Func_Ptr*)(ptr))[0];
            if (mark_func_ptr == 0)
            {
                assert(0);
            }
            mark_func_ptr(ptr);
        }
    }
}

uint64_t __GC_mellow_is_valid_ptr(void* ptr, GC_Env* gc_env)
{
    uint64_t index;
    for (index = 0; index < gc_env->allocs_len; index++)
    {
        if (gc_env->allocs[index].ptr == ptr)
        {
            return 1;
        }
    }
    return 0;
}

void __GC_free_all_allocs(GC_Env* gc_env)
{
    uint64_t i;
    for (i = 0; i < gc_env->allocs_len; i++)
    {
        free(gc_env->allocs[i].ptr);
    }
    free(gc_env->allocs);
    gc_env->allocs = NULL;
    gc_env->allocs_len = 0;
    gc_env->allocs_end = 0;
}

uint64_t __GC_mellow_is_marked(void* ptr)
{
    // First eight bytes are the marking function ptr, second eight bytes are
    // runtime data. First bit of the second eight bytes is the mark bit.
    //
    // The object header is 16 bytes:
    // [8 bytes mark func ptr][1 bit mark bit][7 bits+7 bytes 'util']
    if ((((uint64_t*)(ptr))[1] & 0x8000000000000000) != 0)
    {
        return 1;
    }
    return 0;
}

void __GC_sweep(GC_Env* gc_env)
{
    uint64_t i = 0;
    uint64_t j = gc_env->allocs_len - 1;
    uint64_t num_frees = 0;
    // Move through the allocs array and free everything that needs to be
    // free'd, while keeping the list of valid ptrs contiguous and left-
    // justified. At the end of this loop, both i and j should be equal, and
    // they will represent one-less than the new gc_env->allocs_len value. This
    // algorithm is O(n), as the list of allocs need not be sorted
    for (; i < j; i++)
    {
        if (__GC_mellow_is_marked(gc_env->allocs[i].ptr) == 0)
        {
            // Free the unmarked ptr
            free(gc_env->allocs[i].ptr);
            gc_env->total_allocated -= gc_env->allocs[i].size;
            num_frees++;
            // While rightmost ptr is unmarked, move left in search of a marked
            // ptr, free'ing along the way
            for (; j > i && __GC_mellow_is_marked(gc_env->allocs[j].ptr) == 0; j--)
            {
                free(gc_env->allocs[j].ptr);
                gc_env->total_allocated -= gc_env->allocs[j].size;
                num_frees++;
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
                gc_env->allocs[i].ptr = gc_env->allocs[j].ptr;
                gc_env->allocs[i].size = gc_env->allocs[j].size;
                j--;
            }
        }
    }
    // After this algorithm: gc_env->allocs_len == i == j
    gc_env->allocs_len -= num_frees;
}

void __GC_clear_marks(GC_Env* gc_env)
{
    uint64_t i;
    for (i = 0; i < gc_env->allocs_len; i++)
    {
        // First eight bytes are the marking function ptr, second eight bytes
        // are runtime data. First bit of the first byte of these second eight
        // bytes is the mark bit
        ((uint64_t*)(gc_env->allocs[i].ptr))[1] &= 0x7FFFFFFFFFFFFFFF;
    }
}

void __mellow_GC_mark_string(void* ptr)
{
    // First eight bytes are the marking function ptr, second eight bytes
    // are runtime data. First bit of the first byte of these second eight
    // bytes is the mark bit
    ((uint64_t*)(ptr))[1] |= 0x8000000000000000;
}
