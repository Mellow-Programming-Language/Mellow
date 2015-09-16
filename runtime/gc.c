
#include <stdlib.h>
#include "gc.h"

void* __GC_malloc(size_t alloc_size, GC_Env* gc_env)
{
    void* alloc = malloc(alloc_size);
    add_alloc(alloc, gc_env);
    return alloc;
}

void add_alloc(void* alloc, GC_Env* gc_env)
{
    if (gc_env->allocs == NULL)
    {
        size_t start_size = ALLOCS_START_SIZE;
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
        size_t new_size = gc_env->allocs_end * 2;
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

void free_all_allocs(GC_Env* gc_env)
{
    size_t i;
    for (i = 0; i < gc_env->allocs_len; i++)
    {
        free(gc_env->allocs[i]);
    }
    free(gc_env->allocs);
    gc_env->allocs = NULL;
    gc_env->allocs_len = 0;
    gc_env->allocs_end = 0;
}
