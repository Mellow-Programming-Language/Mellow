#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "stdconv.h"
#include "mellow_internal.h"
#include "../runtime/runtime_vars.h"

// (Mangled) GC marking functions we expect to exist at link time
extern void __mellow_GC_mark_S(void*);
extern void __mellow_GC_mark_ABC(void*);
extern void __mellow_GC_mark_V5Maybe1BC(void*);

int ord(char c)
{
    return (int)c;
}

void* chr(int c)
{
    GC_Env* gc_env = __get_GC_Env();
    struct MaybeChar* maybeChar = (struct MaybeChar*)__GC_malloc_nocollect(
        sizeof(struct MaybeChar), gc_env
    );
    maybeChar->markFunc = __mellow_GC_mark_V5Maybe1BC;
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
    GC_Env* gc_env = __get_GC_Env();
    // The 1 is for space for the null byte
    void* mellowStr = __GC_malloc_nocollect(
        HEAD_SIZE + sizeof(char) + 1,
        gc_env
    );
    // Set the string marking function
    ((void**)mellowStr)[0] = __mellow_GC_mark_S;
    // Set the string length
    ((uint64_t*)mellowStr)[1] = 1;
    // Set the char in the string
    ((uint8_t*)(mellowStr + HEAD_SIZE))[0] = c;
    // Set the null byte
    ((uint8_t*)(mellowStr + HEAD_SIZE))[1] = '\0';
    return mellowStr;
}

void* stringToChars(void* str) {
    GC_Env* gc_env = __get_GC_Env();
    uint64_t strLen = ((uint64_t*)(str + MARK_PTR_SIZE))[0];
    const uint64_t totalSize = HEAD_SIZE + strLen;
    void* mellowArr = __GC_malloc_nocollect(totalSize, gc_env);
    // Set the []char marking function
    ((void**)mellowArr)[0] = __mellow_GC_mark_ABC;
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
        ((uint64_t*)(chs))[1]
    );
}
