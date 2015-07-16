#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "mellow_internal.h"

void* mellow_allocString(const char* str, const uint32_t strLength) {
    // The length of the array of characters plus the bytes allocated to hold
    // the ref-count plus the bytes allocated to hold the string length plus
    // a byte to hold the null byte
    const uint32_t totalSize = strLength + REF_COUNT_SIZE + MELLOW_STR_SIZE + 1;
    void* mellowString = malloc(totalSize);
    // Set the ref-count to 1
    ((uint32_t*)mellowString)[0] = 1;
    // set the str-len to the length of the array of characters
    ((uint32_t*)mellowString)[1] = strLength;
    // Copy the array of chars over
    memcpy(mellowString + REF_COUNT_SIZE + MELLOW_STR_SIZE, str, strLength);
    // Add the null byte
    ((char*)mellowString)[totalSize-1] = '\0';
    return mellowString;
}

void mellow_freeString(void* mellowString) {
    free(mellowString);
}
