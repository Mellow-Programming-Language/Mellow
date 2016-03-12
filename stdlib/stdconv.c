#include <stdlib.h>
#include <stdint.h>
#include "stdconv.h"
#include <string.h>
#include "mellow_internal.h"

int ord(char c)
{
    return (int)c;
}

char chr(int c)
{
    return (char)c;
}

uint32_t byteToInt(uint8_t in)
{
    return (uint32_t)in;
}

uint8_t intToByte(uint32_t in)
{
    return (uint8_t)in;
}

void* charToString(char c)
{
    // The 1 is for space for the null byte
    void* mellowStr = malloc(
        REF_COUNT_SIZE + MELLOW_STR_SIZE + sizeof(char) + 1
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
                             + strLen;
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
