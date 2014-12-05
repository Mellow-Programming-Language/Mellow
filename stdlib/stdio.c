#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "stdio.h"
#include "clam_internal.h"

void writeln(void* clamStr)
{
    // Get the string length at bytes 0-3. The reference count is behind the
    // pointer at bytes -4 through -1
    const size_t strLength = ((uint32_t*)clamStr)[0];
    // The size of the c-string is the size of the clam-string + 1 for the
    // null byte
    const size_t cStrLength = strLength + 1;
    // Allocate space for the c-string
    char* cString = (char*)malloc(cStrLength);
    // Copy the string from the clam-string to cString.
    // Pointer arithmetic + sizeof(uint32_t) to skip past the strLength value
    memcpy(cString, ((char*)clamStr) + CLAM_STR_SIZE, strLength);
    // Add null byte
    cString[cStrLength-1] = '\0';
    printf("%s\n", cString);
    free(cString);
}
