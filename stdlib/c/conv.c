
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "conv.h"
#include "../mellow_internal.h"

void* cStringToString(struct CString* cstring)
{
    const char* str = cstring->str;
    uint32_t strLength = strlen(str);
    // The length of the array of characters plus the bytes allocated to hold
    // the ref-count plus the bytes allocated to hold the string length plus
    // a byte to hold the null byte
    const uint32_t totalSize = HEAD_SIZE + strLength + 1;
    void* mellowString = malloc(totalSize);
    // Set the ref-count to 1
    ((uint32_t*)mellowString)[0] = 1;
    // set the str-len to the length of the array of characters
    ((uint32_t*)mellowString)[1] = strLength;
    // Copy the array of chars over
    memcpy(mellowString + HEAD_SIZE, str, strLength);
    // Add the null byte
    ((char*)mellowString)[totalSize-1] = '\0';

    return mellowString;
}

struct CString* stringToCString(void* mellowString)
{
    uint32_t strLength = ((uint32_t*)mellowString)[1] + 1;
    char* str = (char*)malloc(sizeof(char) * strLength);

    memcpy(str, mellowString + HEAD_SIZE, strLength);

    struct CString* cstring = (struct CString*)malloc(sizeof(struct CString));
    cstring->str = str;

    return cstring;
}
