
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include "gc.h"
#include "ptr_hashset.h"

void __GC_mellow_add_alloc_wrapped(void* ptr, uint64_t size, GC_Env* gc_env)
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

    if (gc_env->allocs_hashset == NULL)
    {
        gc_env->allocs_hashset = (ptr_hashset_t*)calloc(
            sizeof(ptr_hashset_t), 1
        );
        init_ptr_hashset(gc_env->allocs_hashset, 32768);
    }
    add_key(gc_env->allocs_hashset, ptr);

    gc_env->allocs[gc_env->allocs_len].ptr = ptr;
    gc_env->allocs[gc_env->allocs_len].size = size;
    gc_env->allocs_len += 1;
    gc_env->total_allocated += size;
}

// Use this version of the GC allocatior if you're in a context where you want
// to allocate something through the GC, but you want to be sure a collection
// will not start because of it.
//
// The most immediate example of this being _necessary_ is GC allocations from
// within C code, which is executing on the OS stack, not the green thread
// stack, and therefore has a nonsense stack pointer for the purposes of stack
// scanning during collection.
void* __GC_malloc_nocollect(uint64_t size, GC_Env* gc_env)
{
    void* ptr = calloc(size, 1);
    __GC_mellow_add_alloc_wrapped(ptr, size, gc_env);
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
    __GC_mellow_add_alloc_wrapped(ptr, size, gc_env);
    return ptr;
}

void* __GC_realloc_wrapped(
    void* ptr, uint64_t size, GC_Env* gc_env, void** rsp, void** stack_bot
) {
    __GC_remove_alloc(ptr, gc_env);

    void* new_ptr = realloc(ptr, size);
    __GC_mellow_add_alloc_wrapped(new_ptr, size, gc_env);

    return new_ptr;
}

void __GC_remove_alloc(void* ptr, GC_Env* gc_env)
{
    if (!__GC_mellow_is_valid_ptr(ptr, gc_env))
    {
        assert(0);
    }

    // Minus 1 because if the ptr is the last ptr in the list, we're
    // decrementing the length of the valid portion of the allocs array anyway
    uint64_t index;
    for (index = 0; index < gc_env->allocs_len - 1; index++)
    {
        if (gc_env->allocs[index].ptr == ptr)
        {
            gc_env->allocs[index] = gc_env->allocs[gc_env->allocs_len - 1];
        }
    }

    gc_env->allocs_len--;
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

        // If the value is "small" or not eight-byte aligned, it's very, very
        // likely not a real pointer, so skip it. Note that if this heuristic is
        // wrong, this will cause a leak
        if ((uint64_t)ptr < 1024 || ((uint64_t)ptr & 0b111) != 0)
        {
            continue;
        }

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
    return contains_key(gc_env->allocs_hashset, ptr);
}

void __GC_free_all_allocs(GC_Env* gc_env)
{
    if (gc_env->allocs != NULL)
    {
        uint64_t i;
        for (i = 0; i < gc_env->allocs_len; i++)
        {
            free(gc_env->allocs[i].ptr);
        }
        free(gc_env->allocs);
    }

    gc_env->allocs = NULL;
    gc_env->allocs_len = 0;
    gc_env->allocs_end = 0;

    if (gc_env->allocs_hashset != NULL)
    {
        destroy_ptr_hashset(gc_env->allocs_hashset);
        free(gc_env->allocs_hashset);
    }
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
            remove_key(gc_env->allocs_hashset, gc_env->allocs[i].ptr);
            gc_env->total_allocated -= gc_env->allocs[i].size;
            num_frees++;
            // While rightmost ptr is unmarked, move left in search of a marked
            // ptr, free'ing along the way
            for (; j > i && __GC_mellow_is_marked(gc_env->allocs[j].ptr) == 0; j--)
            {
                free(gc_env->allocs[j].ptr);
                remove_key(gc_env->allocs_hashset, gc_env->allocs[j].ptr);
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
