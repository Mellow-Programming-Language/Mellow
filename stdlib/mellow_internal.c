#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "mellow_internal.h"

void* mellow_allocString(const char* str, const uint64_t strLength) {
    // The length of the array of characters plus the bytes allocated to hold
    // the ref-count plus the bytes allocated to hold the string length plus
    // a byte to hold the null byte
    const uint64_t totalSize = HEAD_SIZE + strLength + 1;
    void* mellowString = malloc(totalSize);
    // Set the ref-count to 1
    ((uint64_t*)mellowString)[0] = 1;
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
        ((uint64_t*)(str + RUNTIME_DATA_SIZE))[0]
    );
}

void mellow_freeString(void* mellowString) {
    free(mellowString);
}

void* __arr_arr_append(void* left, void* right,
                       size_t elem_size, uint64_t is_str)
{
    size_t llen = ((uint64_t*)left)[1];
    size_t rlen = ((uint64_t*)right)[1];
    size_t nlen = llen + rlen;
    size_t full_len = HEAD_SIZE + (nlen * elem_size);
    void* new_arr;
    if (is_str != 0)
    {
        // Null byte
        full_len += 1;
        new_arr = malloc(full_len);
        ((uint8_t*)new_arr)[full_len-1] = '\0';
    }
    else
    {
        // No null byte
        new_arr = malloc(full_len);
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
    size_t rlen = ((uint64_t*)right)[1];
    size_t nlen = 1 + rlen;
    size_t full_len = HEAD_SIZE + (nlen * elem_size);
    void* new_arr;
    if (is_str != 0)
    {
        // Null byte
        full_len += 1;
        new_arr = malloc(full_len);
        ((uint8_t*)new_arr)[full_len-1] = '\0';
    }
    else
    {
        // No null byte
        new_arr = malloc(full_len);
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
    size_t llen = ((uint64_t*)left)[1];
    size_t nlen = llen + 1;
    size_t full_len = HEAD_SIZE + (nlen * elem_size);
    void* new_arr;
    if (is_str != 0)
    {
        // Null byte
        full_len += 1;
        new_arr = malloc(full_len);
        ((uint8_t*)new_arr)[full_len-1] = '\0';
    }
    else
    {
        // No null byte
        new_arr = malloc(full_len);
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
    size_t nlen = 1 + 1;
    size_t full_len = HEAD_SIZE + (nlen * elem_size);
    void* new_arr;
    if (is_str != 0)
    {
        // Null byte
        full_len += 1;
        new_arr = malloc(full_len);
        ((uint8_t*)new_arr)[full_len-1] = '\0';
    }
    else
    {
        // No null byte
        new_arr = malloc(full_len);
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
        new_arr = malloc(full_len);
        ((uint8_t*)new_arr)[full_len-1] = '\0';
    }
    else
    {
        new_arr = malloc(HEAD_SIZE + (elem_size * nlen));
    }
    ((uint64_t*)new_arr)[1] = nlen;
    memcpy(
        (uint8_t*)new_arr + HEAD_SIZE,
        (uint8_t*)arr + HEAD_SIZE + (lindex * elem_size),
        nlen * elem_size
    );
    return new_arr;
}
