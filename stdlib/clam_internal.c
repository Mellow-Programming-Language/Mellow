#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "clam_internal.h"

void* allocClamString(const char* str, const uint32_t strLength) {
    const uint32_t totalSize = strLength + REF_COUNT_SIZE + CLAM_STR_SIZE;
    void* clamString = malloc(totalSize);
    ((uint32_t*)clamString)[0] = 1;
    ((uint32_t*)clamString)[1] = strLength;
    memcpy(clamString + REF_COUNT_SIZE + CLAM_STR_SIZE, str, strLength);
    // Return the pointer pointing to just after the refcount
    return ((char*)clamString) + REF_COUNT_SIZE;
}

void freeClamString(void* clamString) {
    free(clamString - REF_COUNT_SIZE);
}
