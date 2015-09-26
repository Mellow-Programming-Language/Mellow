#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include "scheduler.h"
#include "realloc_stack.h"

#ifndef MULTITHREAD

static void* tempstack;

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
    munmap(tempstack, TEMP_STACK_SIZE);
}

#endif

// This function is expected to be executed on a stack other than the stack that
// it is reallocating. It doubles the size of the stack, and since the memory
// might be moved, calculate the value of the new rsp
uint64_t __mremap_stack(ThreadData* thread, const uint64_t rsp)
{
    void* oldStackRaw = thread->t_StackRaw;
    void* oldStackUsable = oldStackRaw + PROT_PAGE_SIZE;
    const size_t oldStackSizeUsable = 1 << thread->stackSize;
    const size_t oldStackSize = oldStackSizeUsable + PROT_PAGE_SIZE;
    thread->stackSize++;
    const size_t newStackSizeUsable = 1 << thread->stackSize;
    const size_t newStackSize = newStackSizeUsable + PROT_PAGE_SIZE;
    // Allocate the new, twice-as-big stack...
    thread->t_StackRaw = (uint8_t*)mmap(
        NULL, newStackSize,
        PROT_READ|PROT_WRITE,
        MAP_PRIVATE|MAP_ANONYMOUS,
        -1, 0
    );
    void* newStackRaw = thread->t_StackRaw;
    void* newStackUsable = newStackRaw + PROT_PAGE_SIZE;
    // Set PROT_NONE on the first page of the new stack allocation, which
    // would be the _top-most_ page of the stack (since the stack grows down),
    // so that instead of running off the end of the stack and clobbering
    // non-stack memory, we summarily segfault. This makes it easier to debug
    // stack memory issues.
    mprotect(newStackRaw, PROT_PAGE_SIZE, PROT_NONE);

    // Set the bottom (where we start, so highest address) of the stack
    thread->t_StackBot = newStackUsable + newStackSizeUsable;
    // Copy the old stack over to this one. Remembering that stacks grow down,
    // we're copying it over to be "right-justified" in the new allocation
    memcpy(
        newStackUsable + oldStackSizeUsable,
        oldStackUsable,
        oldStackSizeUsable
    );
    // Calculate the new rsp value
    // If 0x00[........]0xFF is the whole stack space, we're calculating the
    // length of 0x00[....rsp<used stack space>]0xFF
    uint64_t deltaFromTop = (uint64_t)(
        oldStackUsable + oldStackSizeUsable - rsp
    );
    // Take that same delta from the top of new stack, to get the new rsp
    const uint64_t newRsp = (uint64_t)(
        newStackUsable + newStackSizeUsable - deltaFromTop
    );
    // We need to fix all of the push'd rbp's in the stack, as they all
    // currently point to locations in the old stack, meaning every single
    // one of them wants us to segfault. Luckily, each rbp points to the
    // previous rbp, all the way down, so just follow them like a pointer
    // linked-list, fixing them as well go to point to their analog in the
    // new stack allocation
    uint64_t old_rbp_index = (rsp - (uint64_t)oldStackUsable) / 8;
    uint64_t old_rbp = ((uint64_t*)oldStackUsable)[old_rbp_index];
    while (old_rbp >= (uint64_t)oldStackUsable
        && old_rbp <= (uint64_t)(oldStackUsable + oldStackSizeUsable))
    {
        deltaFromTop = (uint64_t)(
            oldStackUsable + oldStackSizeUsable - old_rbp
        );
        uint64_t new_rbp = (uint64_t)(
            newStackUsable + newStackSizeUsable - deltaFromTop
        );
        uint64_t new_raw_index = old_rbp_index + (oldStackSizeUsable / 8);
        ((uint64_t*)newStackUsable)[new_raw_index] = new_rbp;
        old_rbp_index = (old_rbp - (uint64_t)oldStackUsable) / 8;
        old_rbp = ((uint64_t*)oldStackUsable)[old_rbp_index];
    }
    // Free the old stack
    munmap(oldStackRaw, oldStackSize);

    return newRsp;
}
