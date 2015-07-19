#include <stdlib.h>
#include <stdint.h>
#include "stdconv.h"
#include "mellow_internal.h"

int ord(char c)
{
    return (int)c;
}

void* charToString(char c)
{
    uint32_t allocSize = getAllocSize(1);
    // The 1 is for space for the null byte
    void* mellowStr = malloc(
        REF_COUNT_SIZE + MELLOW_STR_SIZE + allocSize + 1
    );
    // Set the ref count
    ((uint32_t*)mellowStr)[0] = 1;
    // Set the string length
    ((uint32_t*)mellowStr)[1] = 1;
    // Set the char in the string
    ((uint32_t*)mellowStr)[2] = c;
    // Set the null byte
    ((uint32_t*)mellowStr)[3] = '\0';
    return mellowStr;
}
