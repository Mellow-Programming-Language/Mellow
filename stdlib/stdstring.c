#include <stdint.h>
#include "mellow_internal.h"

void* toLower(void* str)
{
    void* copy = mellow_copyString(str);
    uint64_t len = ((uint64_t*)(copy + RUNTIME_DATA_SIZE))[0];
    char* chs = (char*)(copy + HEAD_SIZE);
    uint64_t i;
    for (i = 0; i < len; i++)
    {
        if (chs[i] >= 'A' && chs[i] <= 'Z') {
            chs[i] = chs[i] + 32;
        }
    }
    return copy;
}

void* toUpper(void* str)
{
    void* copy = mellow_copyString(str);
    uint64_t len = ((uint64_t*)(copy + RUNTIME_DATA_SIZE))[0];
    char* chs = (char*)(copy + HEAD_SIZE);
    uint64_t i;
    for (i = 0; i < len; i++)
    {
        if (chs[i] >= 'a' && chs[i] <= 'z') {
            chs[i] = chs[i] - 32;
        }
    }
    return copy;
}
