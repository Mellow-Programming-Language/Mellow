
// This file is used to generate 'tls.asm'. 'tls.asm' is expected to be as bare
// as possible, as in not creating a stack frame or writing to any unnecessary
// registers. Since NASM does not document TLS well at all, GAS is used to
// assemble 'tls.asm' for linking back into 'callFunc.asm', and the runtime as
// a whole.

#include <stddef.h>
#include <sys/mman.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h> // for sysconf
#include "realloc_stack.h"
#include "tls.h"

void* __get_tempstack()
{
    return tempstack;
}

void __init_tempstack()
{
    tempstack = mmap(
        NULL, TEMP_STACK_SIZE,
        PROT_READ|PROT_WRITE,
        MAP_PRIVATE|MAP_ANONYMOUS,
        -1, 0
    );
}

void __free_tempstack()
{
    // free(tempstack);
    munmap(tempstack, TEMP_STACK_SIZE);
}

void* get_currentthread()
{
    return currentthread;
}

void set_currentthread(void* val)
{
    currentthread = val;
}

void* get_mainstack()
{
    return mainstack;
}

void set_mainstack(void* val)
{
    mainstack = val;
}
