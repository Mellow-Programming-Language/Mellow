#ifndef CLAM_INTERNAL_H
#define CLAM_INTERNAL_H

#include <stdint.h>

// clam-string:
// [4 bytes ref-count, 4 bytes string length, len bytes char[] space], where
// a proper clam-string pointer is pointing at the beginning of the string
// length field.

#define REF_COUNT_SIZE (sizeof(uint32_t))
#define CLAM_STR_SIZE (sizeof(uint32_t))

// Allocate space for a full clam string, update ref-count to 1, populate length
// field, copy c-string into allocated space for string, and return pointer
// pointing just past the reference count, pointing at the beginning of the
// length field
void* allocClamString(const char* str, const uint32_t length);

// Deallocate all memory allocated by allocClamString()
void freeClamString(void* clamString);

#endif
