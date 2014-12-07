#ifndef CLAM_INTERNAL_H
#define CLAM_INTERNAL_H

#include <stdint.h>

// clam-string:
// [uint32_t ref-count, uint32_t string length, len bytes char[], 1 null-byte]

// clam-maybe:
// [uint32_t ref-count, uint32_t variant tag, max-size of each constructor
//  value tuple]
// Tag 0: Some
// Tag 1: None

#define CLAM_PTR_SIZE (sizeof(char*))
#define REF_COUNT_SIZE (sizeof(uint32_t))
#define CLAM_STR_SIZE (sizeof(uint32_t))
#define STR_START_OFFSET (REF_COUNT_SIZE + CLAM_STR_SIZE)
#define VARIANT_TAG_SIZE (sizeof(uint32_t))

// Allocate space for a full clam string, update ref-count to 1, populate length
// field, copy c-string into allocated space for string, add null byte to end,
// and return pointer to beginning of allocated memory for clam-string
void* clam_allocString(const char* str, const uint32_t length);

// Deallocate all memory allocated by clam_allocString()
void clam_freeString(void* clamString);

#endif
