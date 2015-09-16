
#ifndef GC_H
#define GC_H

#define ALLOCS_START_SIZE 64

typedef struct {
    void** allocs;
    size_t allocs_len;
    size_t allocs_end;
} GC_Env;

#endif
