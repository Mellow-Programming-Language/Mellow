#include <stdint.h>
#include "mellow_internal.h"

void* toLower(void* str)
{
    void* copy = mellow_copyString(str);
    uint32_t len = ((uint32_t*)(copy + REF_COUNT_SIZE))[0];
    char* chs = (char*)(copy + REF_COUNT_SIZE + MELLOW_STR_SIZE);
    uint32_t i;
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
    uint32_t len = ((uint32_t*)(copy + REF_COUNT_SIZE))[0];
    char* chs = (char*)(copy + REF_COUNT_SIZE + MELLOW_STR_SIZE);
    uint32_t i;
    for (i = 0; i < len; i++)
    {
        if (chs[i] >= 'a' && chs[i] <= 'z') {
            chs[i] = chs[i] - 32;
        }
    }
    return copy;
}
