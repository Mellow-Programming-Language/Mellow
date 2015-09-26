
#ifndef REALLOC_STACK_H
#define REALLOC_STACK_H

#include <stdint.h>
#include "scheduler.h"

#define TEMP_STACK_SIZE (4096)
// Size of the PROT_NONE page that sits at the end of (behind) the stack
// allocated for each thread, so that if we _do_ run off the end of the stack
// (likely from a rampant C library call, since we otherwise are intelligent
// about growing our stacks), we'll summarily segfault, rather than clobbering
// other memory that might have been contiguously allocated (to the left of)
// our stack (since stacks grow down! (left))
#define PROT_PAGE_SIZE (4096)

uint64_t __mremap_stack(ThreadData* thread, const uint64_t rsp);

#ifdef MULTITHREAD

extern void __init_tempstack();
extern void __free_tempstack();

#else

void* __get_tempstack();
void __init_tempstack();
void __free_tempstack();

#endif

#endif
