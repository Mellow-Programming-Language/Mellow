#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "stdconv.h"
#include "mellow_internal.h"
#include "../runtime/runtime_vars.h"

int ord(char c)
{
    return (int)c;
}

void* chr(int c)
{
    // GC_Env* gc_env = __get_GC_Env();
    // struct MaybeChar* maybeChar =
    //     (struct MaybeChar*)__GC_malloc(sizeof(struct MaybeChar), gc_env);
    struct MaybeChar* maybeChar = (struct MaybeChar*)malloc(
        sizeof(struct MaybeChar)
    );
    maybeChar->runtimeData = 0;
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
    // GC_Env* gc_env = __get_GC_Env();
    // The 1 is for space for the null byte
    // void* mellowStr = __GC_malloc(
    //     HEAD_SIZE + sizeof(char) + 1,
    //     gc_env
    // );
    void* mellowStr = malloc(HEAD_SIZE + sizeof(char) + 1);
    // Clear the "runtime" header
    ((uint64_t*)mellowStr)[0] = 1;
    // Set the string length
    ((uint64_t*)mellowStr)[1] = 1;
    // Set the char in the string
    ((uint8_t*)(mellowStr + HEAD_SIZE))[0] = c;
    // Set the null byte
    ((uint8_t*)(mellowStr + HEAD_SIZE))[1] = '\0';
    return mellowStr;
}

void* stringToChars(void* str) {
    // GC_Env* gc_env = __get_GC_Env();
    uint64_t strLen = ((uint64_t*)(str + MARK_PTR_SIZE))[0];
    const uint64_t totalSize = HEAD_SIZE + strLen;
    // void* mellowArr = __GC_malloc(totalSize, gc_env);
    void* mellowArr = malloc(totalSize);
    ((uint64_t*)mellowArr)[0] = 1;
    ((uint64_t*)mellowArr)[1] = strLen;
    memcpy(
        mellowArr + HEAD_SIZE,
        str + HEAD_SIZE,
        strLen
    );
    return mellowArr;
}

void* charsToString(void* chs) {
    return mellow_allocString(
        chs + HEAD_SIZE,
        ((uint64_t*)(chs + MARK_PTR_SIZE))[0]
    );
}
