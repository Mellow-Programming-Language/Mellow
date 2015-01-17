#ifndef SCHEDULER_H
#define SCHEDULER_H

#include <stdint.h>

#define THREAD_DATA_ARR_START_LEN 4
#define THREAD_DATA_ARR_MUL_INCREASE 2
#define THREAD_STACK_SIZE (4096*64)

typedef struct
{
    // Address of function to exec
    void* funcAddr;
    // Current position in function (0 if start of function)
    // Will be the value that eip needs to be to continue execution
    void* curFuncAddr;
    // Pointer to bottom of allocated stack (that grows DOWNWARD). That is,
    // this is a pointer to the highest address valid in the stack
    uint8_t* t_StackBot;
    // This is a pointer to the current value of the stack as should be used
    // for execution. That is, after returning to this thread from being
    // yielded away from it, set rsp to this value
    uint8_t* t_StackCur;
    // Pointer to the beginning of the memory area allocated for the stack.
    // This is what was originally returned by mmap, and what should be used
    // with munmap
    uint8_t* t_StackRaw;
    // ebp of thread, other portion of saving stack information. 0 if un-init
    uint8_t* t_rbp;
    // Whether this thread has finished execution or not. Non-zero if still
    // valid, 0 if the thread is finished or the thread has not started yet.
    // That is to say, the thread is finished if curFuncAddr is non-zero and
    // stillValid is 0, and the thread is still valid if stillValid != 0 OR
    // curFuncAddr == 0
    uint8_t stillValid;
    // Amount of bytes that were used for the stack allocation of arguments
    uint32_t stackArgsSize;
    // Memory populated with the function arguments to be placed in registers
    // in a canned way in callFunc
    void* regVars;
} ThreadData;

extern void callFunc(ThreadData* curThread);
extern void yield();

// The size values in argLens can be positive or negative. If they're positive,
// then it's an int val that must appear either in an r-family register,
// or on the stack after the sixth integer argument. If they're negative,
// then it's a float val that must appear either in an x-family register,
// or on the stack after the eighth integer argument
void newProc(uint32_t argBytes, void* funcAddr, int8_t* argLens, void* args);

void printThreadData(ThreadData* curThread);

void callThreadFunc(ThreadData* thread);

void deallocThreadData(ThreadData* thread);

typedef struct
{
    // Array of managed green threads
    ThreadData** threadArr;
    // Length of managed green threads array
    uint32_t threadArrLen;
    // Index one past last valid ThreadData in threadArr
    uint32_t threadArrIndex;
} GlobalThreadMem;

void initThreadManager();

void takedownThreadManager();

// void addThreadData(uint32_t argBytes, void* funcAddr, ...);

void execScheduler();

#endif
