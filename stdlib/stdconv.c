#include <stdlib.h>
#include <stdint.h>
#include "stdconv.h"
#include <string.h>
#include "mellow_internal.h"

int ord(char c)
{
    return (int)c;
}

void* chr(int c)
{
    struct MaybeChar* maybeChar =
        (struct MaybeChar*)malloc(sizeof(struct MaybeChar));
    maybeChar->refCount = 1;
    if (c <= 0xFF)
    {
        // Set tag to Some
        maybeChar->variantTag = 0;
        maybeChar->c = (char)c;
    }
    else
    {
        // Set tag to None
        maybeChar->variantTag = 1;
    }
    return maybeChar;
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

void* stringToChars(void* str) {
    uint32_t strLen = ((uint32_t*)(str + REF_COUNT_SIZE))[0];
    const uint32_t totalSize = REF_COUNT_SIZE
                             + MELLOW_STR_SIZE
                             + getAllocSize(strLen);
    void* mellowArr = malloc(totalSize);
    ((uint32_t*)mellowArr)[0] = 1;
    ((uint32_t*)mellowArr)[1] = strLen;
    memcpy(
        mellowArr + REF_COUNT_SIZE + MELLOW_STR_SIZE,
        str + REF_COUNT_SIZE + MELLOW_STR_SIZE,
        strLen
    );
    return mellowArr;
}

void* charsToString(void* chs) {
    return mellow_allocString(
        chs + REF_COUNT_SIZE + MELLOW_STR_SIZE,
        ((uint32_t*)(chs + REF_COUNT_SIZE))[0]
    );
}
