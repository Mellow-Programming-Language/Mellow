#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "clam_internal.h"

void* clam_allocString(const char* str, const uint32_t strLength) {
    // The length of the array of characters plus the bytes allocated to hold
    // the ref-count plus the bytes allocated to hold the string length plus
    // a byte to hold the null byte
    const uint32_t totalSize = strLength + REF_COUNT_SIZE + CLAM_STR_SIZE + 1;
    void* clamString = malloc(totalSize);
    // Set the ref-count to 1
    ((uint32_t*)clamString)[0] = 1;
    // set the str-len to the length of the array of characters
    ((uint32_t*)clamString)[1] = strLength;
    // Copy the array of chars over
    memcpy(clamString + REF_COUNT_SIZE + CLAM_STR_SIZE, str, strLength);
    // Add the null byte
    ((char*)clamString)[totalSize-1] = '\0';
    return clamString;
}

void clam_freeString(void* clamString) {
    free(clamString);
}
