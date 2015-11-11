#ifndef MELLOW_INTERNAL_H
#define MELLOW_INTERNAL_H

#include <stddef.h>
#include <stdint.h>

// mellow-string:
// [
//     uint64_t runtime header, uint64_t string length, len bytes char[],
//     1 null-byte
// ]

// mellow-maybe:
// [
//     uint64_t runtime header, uint64_t variant tag,
//     max-size of each constructor value tuple
// ]
// Tag 0: Some
// Tag 1: None

#define MELLOW_PTR_SIZE (sizeof(char*))
#define RUNTIME_DATA_SIZE (8)
#define LEN_SIZE (8)
#define HEAD_SIZE (RUNTIME_DATA_SIZE + LEN_SIZE)

// Allocate space for a full mellow string, populate length field, copy c-string
// into allocated space for string, add null byte to end, and return pointer to
// beginning of allocated memory for mellow-string
void* mellow_allocString(const char* str, const uint64_t length);
// Make a copy of the string
void* mellow_copyString(void* str);

void* __arr_arr_append(void* left, void* right,
                       size_t elem_size, uint64_t is_str);

void* __elem_arr_append(uint64_t left, void* right,
                        size_t elem_size, uint64_t is_str);

void* __arr_elem_append(void* left, uint64_t right,
                        size_t elem_size, uint64_t is_str);

void* __elem_elem_append(uint64_t left, uint64_t right,
                         size_t elem_size, uint64_t is_str);

void* __arr_slice(void* arr, uint64_t lindex, uint64_t rindex,
                  uint64_t elem_size, uint64_t is_str);

#endif
