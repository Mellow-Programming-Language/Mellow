#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "mellow_internal.h"
#include "../runtime/gc.h"
#include "../runtime/runtime_vars.h"

extern void __mellow_GC_mark_S(void*);
extern void __mellow_GC_mark_AS(void*);

void* mellow_allocString(const char* str, const uint64_t strLength)
{
    GC_Env* gc_env = __get_GC_Env();
    // The length of the array of characters plus the bytes allocated to hold
    // the runtime header plus the bytes allocated to hold the string length
    // plus a byte to hold the null byte
    const uint64_t totalSize = HEAD_SIZE + strLength + 1;
    void* mellowString = __GC_malloc_nocollect(totalSize, gc_env);
    // Set string marking function
    ((Marking_Func_Ptr*)mellowString)[0] = __mellow_GC_mark_S;
    // set the str-len to the length of the array of characters
    ((uint64_t*)mellowString)[1] = strLength;
    // Copy the array of chars over
    memcpy(mellowString + HEAD_SIZE, str, strLength);
    // Add the null byte
    ((char*)mellowString)[totalSize-1] = '\0';
    return mellowString;
}

void* mellow_copyString(void* str)
{
    return mellow_allocString(
        (char*)(str + HEAD_SIZE),
        ((uint64_t*)(str + MARK_PTR_SIZE))[0]
    );
}

void* __get_mellow_argv(int argc, char** argv)
{
    GC_Env* gc_env = __get_GC_Env();
    size_t num_entries = argc * sizeof(void*);
    void* new_argv = __GC_malloc(HEAD_SIZE + num_entries, gc_env);
    // Set string marking function
    ((Marking_Func_Ptr*)new_argv)[0] = __mellow_GC_mark_AS;
    // Set array length
    ((uint64_t*)new_argv)[1] = argc;
    uint64_t i;
    for (i = 0; i < argc; i++)
    {
        size_t char_count = strlen(argv[i]);
        size_t str_len = char_count + 1;
        void* mellow_str = __GC_malloc(HEAD_SIZE + str_len, gc_env);
        // Set string marking function
        ((Marking_Func_Ptr*)mellow_str)[0] = __mellow_GC_mark_S;
        // Set string length
        ((uint64_t*)mellow_str)[1] = char_count;
        // Copy the string, including the null terminator
        memcpy(
            (uint8_t*)mellow_str + HEAD_SIZE,
            (uint8_t*)argv[i],
            str_len
        );
        // Populate the mellow argv with the new string. Indices 0 and 1 are
        // header indices, so start at index 2
        ((void**)new_argv)[i+2] = mellow_str;
    }
    return new_argv;
}

void* __arr_arr_append(void* left, void* right,
                       size_t elem_size, uint64_t is_str)
{
    GC_Env* gc_env = __get_GC_Env();
    size_t llen = ((uint64_t*)left)[1];
    size_t rlen = ((uint64_t*)right)[1];
    size_t nlen = llen + rlen;
    size_t full_len = HEAD_SIZE + (nlen * elem_size);
    void* new_arr;
    if (is_str != 0)
    {
        // Null byte
        full_len += 1;
        new_arr = __GC_malloc(full_len, gc_env);
        ((uint8_t*)new_arr)[full_len-1] = '\0';
    }
    else
    {
        // No null byte
        new_arr = __GC_malloc(full_len, gc_env);
    }
    ((uint64_t*)new_arr)[1] = nlen;
    memcpy(
        (uint8_t*)new_arr + HEAD_SIZE,
        (uint8_t*)left + HEAD_SIZE,
        llen * elem_size
    );
    memcpy(
        (uint8_t*)new_arr + HEAD_SIZE + (llen * elem_size),
        (uint8_t*)right + HEAD_SIZE,
        rlen * elem_size
    );
    return new_arr;
}

void* __elem_arr_append(uint64_t left, void* right,
                        size_t elem_size, uint64_t is_str)
{
    GC_Env* gc_env = __get_GC_Env();
    size_t rlen = ((uint64_t*)right)[1];
    size_t nlen = 1 + rlen;
    size_t full_len = HEAD_SIZE + (nlen * elem_size);
    void* new_arr;
    if (is_str != 0)
    {
        // Null byte
        full_len += 1;
        new_arr = __GC_malloc(full_len, gc_env);
        ((uint8_t*)new_arr)[full_len-1] = '\0';
    }
    else
    {
        // No null byte
        new_arr = __GC_malloc(full_len, gc_env);
    }
    ((uint64_t*)new_arr)[1] = nlen;
    memcpy(
        (uint8_t*)new_arr + HEAD_SIZE,
        &left,
        elem_size
    );
    memcpy(
        (uint8_t*)new_arr + HEAD_SIZE + elem_size,
        (uint8_t*)right + HEAD_SIZE,
        rlen * elem_size
    );
    return new_arr;
}

void* __arr_elem_append(void* left, uint64_t right,
                        size_t elem_size, uint64_t is_str)
{
    GC_Env* gc_env = __get_GC_Env();
    size_t llen = ((uint64_t*)left)[1];
    size_t nlen = llen + 1;
    size_t full_len = HEAD_SIZE + (nlen * elem_size);
    void* new_arr;
    if (is_str != 0)
    {
        // Null byte
        full_len += 1;
        new_arr = __GC_malloc(full_len, gc_env);
        ((uint8_t*)new_arr)[full_len-1] = '\0';
    }
    else
    {
        // No null byte
        new_arr = __GC_malloc(full_len, gc_env);
    }
    ((uint64_t*)new_arr)[1] = nlen;
    memcpy(
        (uint8_t*)new_arr + HEAD_SIZE,
        (uint8_t*)left + HEAD_SIZE,
        llen * elem_size
    );
    memcpy(
        (uint8_t*)new_arr + HEAD_SIZE + (llen * elem_size),
        &right,
        elem_size
    );
    return new_arr;
}

void* __elem_elem_append(uint64_t left, uint64_t right,
                         size_t elem_size, uint64_t is_str)
{
    GC_Env* gc_env = __get_GC_Env();
    size_t nlen = 1 + 1;
    size_t full_len = HEAD_SIZE + (nlen * elem_size);
    void* new_arr;
    if (is_str != 0)
    {
        // Null byte
        full_len += 1;
        new_arr = __GC_malloc(full_len, gc_env);
        ((uint8_t*)new_arr)[full_len-1] = '\0';
    }
    else
    {
        // No null byte
        new_arr = __GC_malloc(full_len, gc_env);
    }
    ((uint64_t*)new_arr)[1] = nlen;
    memcpy(
        (uint8_t*)new_arr + HEAD_SIZE,
        &left,
        elem_size
    );
    memcpy(
        (uint8_t*)new_arr + HEAD_SIZE + elem_size,
        &right,
        elem_size
    );
    return new_arr;
}

void* __arr_slice(void* arr, uint64_t lindex, uint64_t rindex,
                  uint64_t elem_size, uint64_t is_str)
{
    GC_Env* gc_env = __get_GC_Env();
    size_t len = ((uint64_t*)arr)[1];
    size_t nlen;
    void* new_arr;
    if (lindex >= rindex || lindex >= len)
    {
        nlen = 0;
    }
    else
    {
        if (rindex > len)
        {
            rindex = len;
        }
        nlen = rindex - lindex;
    }
    if (is_str != 0)
    {
        size_t full_len = HEAD_SIZE + (elem_size * nlen) + 1;
        new_arr = __GC_malloc(full_len, gc_env);
        ((uint8_t*)new_arr)[full_len-1] = '\0';
    }
    else
    {
        new_arr = __GC_malloc(HEAD_SIZE + (elem_size * nlen), gc_env);
    }
    ((uint64_t*)new_arr)[1] = nlen;
    memcpy(
        (uint8_t*)new_arr + HEAD_SIZE,
        (uint8_t*)arr + HEAD_SIZE + (lindex * elem_size),
        nlen * elem_size
    );
    return new_arr;
}
