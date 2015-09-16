
#ifndef GC_H
#define GC_H

#include <stdint.h>

#define ALLOCS_START_SIZE 64

typedef struct {
    void** allocs;
    uint64_t allocs_len;
    uint64_t allocs_end;
} GC_Env;

#endif
