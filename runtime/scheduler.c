#define _GNU_SOURCE
#include <assert.h>
#include <inttypes.h> // So we can printf uint_t types
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdarg.h>
#include <stddef.h>
#include <sys/mman.h>
#include <unistd.h> // for sysconf
#include "realloc_stack.h"
#include "scheduler.h"
#include "gc.h"

static GlobalThreadMem* g_threadManager = NULL;

static volatile uint64_t numCores;
static volatile uint64_t numThreads;

static const uint64_t CHAN_MUTEXES_PER_CORE = 8;
static volatile uint64_t chan_mutexes_count;
static pthread_mutex_t chan_alloc_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t* chan_access_mutexes;
static volatile uint64_t chan_mutex_accumulator_index = 0;

#ifdef MULTITHREAD

typedef enum
{
    INVALID,
    SCHEDULED,
    RUNNING
} scheduled_thread_state;

typedef struct
{
    ThreadData* threadData;
    scheduled_thread_state valid;
} SchedulerData;

static pthread_mutex_t runtime_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_t* kernelThreads;
static volatile SchedulerData* schedulerData;
static volatile uint64_t programDone = 0;
static pthread_cond_t* cond_workers;
static pthread_cond_t* cond_scheduler;

#endif

void printThreadData(ThreadData* curThread, int32_t v)
{
    printf("Print Thread Data:\n");
    printf("    ThreadData* curThread %d: %p\n",          v, curThread);
    printf("    funcAddr              %d: %p\n",          v, curThread->funcAddr);
    printf("    curFuncAddr           %d: %p\n",          v, curThread->curFuncAddr);
    printf("    t_StackBot            %d: %p\n",          v, curThread->t_StackBot);
    printf("    t_StackCur            %d: %p\n",          v, curThread->t_StackCur);
    printf("    t_StackRaw            %d: %p\n",          v, curThread->t_StackRaw);
    printf("    t_rbp                 %d: %p\n",          v, curThread->t_rbp);
    printf("    stillValid            %d: %u\n",          v, curThread->stillValid);
    printf("    stackSize             %d: %" PRIu8 "\n",  v, curThread->stackSize);
    printf("    stackArgsSize         %d: %" PRIu32 "\n", v, curThread->stackArgsSize);
    printf("    regVars               %d: %p\n",          v, curThread->regVars);
}

void callThreadFunc(ThreadData* thread)
{
    callFunc(thread);
}

void deallocThreadData(ThreadData* thread)
{
    GC_Env* gcEnv = thread->gcEnv;
    if (gcEnv != NULL)
    {
        __GC_free_all_allocs(gcEnv);
        free(gcEnv);
        thread->gcEnv = NULL;
    }

    // Unmap memory allocated for thread stack
    munmap(thread->t_StackRaw, 1 << thread->stackSize);
    // Dealloc memory for struct
    free(thread);
}

void initThreadManager()
{
    // Alloc space for struct
    g_threadManager = (GlobalThreadMem*)malloc(sizeof(GlobalThreadMem));
    // Alloc initial space for ThreadData* array
    g_threadManager->threadArr =
        (ThreadData**)malloc(sizeof(ThreadData*) * THREAD_DATA_ARR_START_LEN);
    // Init ThreadData* array length tracker
    g_threadManager->threadArrLen = THREAD_DATA_ARR_START_LEN;
    // Init ThreadData* array index tracker
    g_threadManager->threadArrIndex = 0;

    numCores = sysconf(_SC_NPROCESSORS_ONLN);
    numThreads = numCores;

    // Initialize the access mutexes used by allocated channels. Each created
    // channel will be assigned a number corresponding to one of these mutexes,
    // and will always use that mutex for channel accesses. This way, the
    // probability of lock contention between two different channels is
    // minimized, while avoiding allocating a different mutex for each channel
    chan_mutexes_count = numCores * CHAN_MUTEXES_PER_CORE;
    chan_access_mutexes = (pthread_mutex_t*)malloc(
        sizeof(pthread_mutex_t) * chan_mutexes_count
    );
    uint64_t i;
    for (i = 0; i < chan_mutexes_count; i++)
    {
        pthread_mutex_init(&chan_access_mutexes[i], NULL);
    }

#ifdef MULTITHREAD
    cond_workers = (pthread_cond_t*)malloc(sizeof(pthread_cond_t));
    cond_scheduler = (pthread_cond_t*)malloc(sizeof(pthread_cond_t));
    // Initialize the worker kthreads condition variable
    pthread_cond_init(cond_workers, NULL);
    // Initialize the scheduler condition variable
    pthread_cond_init(cond_scheduler, NULL);
#endif
}

uint64_t __mellow_get_chan_mutex_index()
{
    uint64_t cur_index;

    pthread_mutex_lock(&chan_alloc_mutex);

    cur_index = chan_mutex_accumulator_index;
    chan_mutex_accumulator_index++;
    if (chan_mutex_accumulator_index >= chan_mutexes_count)
    {
        chan_mutex_accumulator_index = 0;
    }

    pthread_mutex_unlock(&chan_alloc_mutex);

    return cur_index;
}

void __mellow_lock_chan_access_mutex(uint64_t index)
{
    pthread_mutex_lock(&chan_access_mutexes[index]);
}

void __mellow_unlock_chan_access_mutex(uint64_t index)
{
    pthread_mutex_unlock(&chan_access_mutexes[index]);
}

void takedownThreadManager()
{
    uint32_t i;
    // Loop over all valid ThreadData* and dealloc them
    for (i = 0; i < g_threadManager->threadArrIndex; i++)
    {
        deallocThreadData(g_threadManager->threadArr[i]);
    }
    // Dealloc memory for ThreadData*
    free(g_threadManager->threadArr);
    // Dealloc memory for struct
    free(g_threadManager);

    free(chan_access_mutexes);

#ifdef MULTITHREAD
    pthread_cond_destroy(cond_workers);
    pthread_cond_destroy(cond_scheduler);
    free(cond_workers);
    free(cond_scheduler);
#endif
}

void newProc(uint32_t numArgs, void* funcAddr, int8_t* argLens, void* args)
{
    // Alloc new ThreadData
    ThreadData* newThread = (ThreadData*)malloc(sizeof(ThreadData));
    // Init the address of the function this green thread manages
    newThread->funcAddr = funcAddr;
    // Init the instruction position within the function. 0 means the
    // beginning of the function, and curFuncAddr will later take on the
    // role of remembering the eip instruction pointer
    newThread->curFuncAddr = 0;
    // Thread starts off 0, meaning curFuncAddr should also be checked
    // to see if the thread simply hasn't started yet
    newThread->stillValid = 0;
    // Thread starts off with unitialized stack frame pointer
    newThread->t_rbp = 0;
    const size_t stackSizeUsable = 1 << THREAD_STACK_SIZE_EXP;
    // Set starting stack size
    const size_t stackSize = stackSizeUsable + PROT_PAGE_SIZE;
    newThread->stackSize = THREAD_STACK_SIZE_EXP;

    newThread->t_StackRaw = NULL;
    // mmap thread stack
    newThread->t_StackRaw = (uint8_t*)mmap(NULL, stackSize,
                                           PROT_READ|PROT_WRITE,
                                           MAP_PRIVATE|MAP_ANONYMOUS,
                                           -1, 0);
    void* newStackRaw = newThread->t_StackRaw;
    void* newStackUsable = newStackRaw + PROT_PAGE_SIZE;

    // Clear the stack memory, for sanity's sake
    memset(newStackRaw, 0, stackSize);

    // Set PROT_NONE on the first page of the new stack allocation, which
    // would be the _top-most_ page of the stack (since the stack grows down),
    // so that instead of running off the end of the stack and clobbering
    // non-stack memory, we summarily segfault. This makes it easier to debug
    // stack memory issues.
    mprotect(newStackRaw, PROT_PAGE_SIZE, PROT_NONE);

    // StackCur starts as a meaningless pointer
    newThread->t_StackCur = 0;
    // Make t_StackBot point to "bottom" of stack (highest address)
    newThread->t_StackBot = newStackUsable + stackSizeUsable;

    // TODO finish putting things on the stack. Note that this is tricky because
    // after the 6th (or 8th, in the case of floats) register is accounted for,
    // arguments are then supposed to appear on the stack backwards, as in
    // the last argument pushed first. So this isn't straightforward. We're
    // probably gonna need to go through the args once to figure out what needs
    // to be on the stack, and then go through them again backwards, actually
    // doing it

    // This is an overallocation for the stack vars
    void* stackVars = malloc(numArgs * 8);
    // 8 * 6 bytes for the int registers, and 8 * 8 bytes for the xmm registers
    void* regVars = malloc((8 * 6) + (8 * 8));
    // Place any int args past the sixth int arg and any float args past the
    // 8th float arg onto the stack
    uint32_t intArgsIndex = 0;
    uint32_t floatArgsIndex = 0;
    uint32_t i = 0;
    uint32_t onStack = 0;
    for (; i < numArgs; i++)
    {
        if (argLens[i] > 0)
        {
            // Put the argument on the stack
            if (intArgsIndex >= 6)
            {
                ((uint64_t*)stackVars)[onStack] = ((uint64_t*)args)[i];
                onStack++;
            }
            // Put the argument in the memory allocated for argument registers
            else
            {
                ((uint64_t*)regVars)[intArgsIndex] = ((uint64_t*)args)[i];
            }
            intArgsIndex++;
        }
        else
        {
            // Put the argument on the stack
            if (floatArgsIndex >= 8)
            {
                ((double*)stackVars)[onStack] = ((double*)args)[i];
                onStack++;
            }
            // Put the argument in the memory allocated for argument registers
            else
            {
                // Jump the pointer forward 48 bytes, past where the int reg
                // stuff goes
                ((double*)regVars + (8 * 6))[floatArgsIndex]
                    = ((double*)args)[i];
            }
            floatArgsIndex++;
        }
    }
    if (onStack > 0)
    {
        for (i = onStack - 1; i >= 0; i--)
        {
            ((uint64_t*)newThread->t_StackBot - i * 8)[0]
                = ((uint64_t*)stackVars)[i];
        }
    }
    free(stackVars);
    newThread->regVars = regVars;
    // Number of bytes allocated for arguments on stack
    newThread->stackArgsSize = onStack * 8;
#ifdef MULTITHREAD
    pthread_mutex_lock(&runtime_mutex);
#endif
    // Put newThread into global thread manager, allocating space for the
    // pointer if necessary. Check first if we need to allocate more memory
    if (g_threadManager->threadArrIndex >= g_threadManager->threadArrLen)
    {
        const uint64_t growth_factor =
            g_threadManager->threadArrLen * THREAD_DATA_ARR_MUL_INCREASE;
        // Allocate more space for thread manager
        g_threadManager->threadArr = (ThreadData**)realloc(
            g_threadManager->threadArr,
            sizeof(ThreadData*) * growth_factor);
        g_threadManager->threadArrLen = growth_factor;
    }
    // Place pointer into ThreadData* array
    g_threadManager->threadArr[g_threadManager->threadArrIndex] = newThread;
    // Increment index
    g_threadManager->threadArrIndex++;
#ifdef MULTITHREAD
    pthread_mutex_unlock(&runtime_mutex);
#endif
}

void execScheduler()
{
#ifdef MULTITHREAD
    kernelThreads = (pthread_t*)malloc(numThreads * sizeof(pthread_t));
    schedulerData = (SchedulerData*)malloc(numThreads * sizeof(SchedulerData));
    uint64_t i;
    // The scheduler queue must be initialized fully first!
    for (i = 0; i < numThreads; i++)
    {
        schedulerData[i].valid = INVALID;
        schedulerData[i].threadData = NULL;
    }
    for (i = 0; i < numThreads; i++)
    {
        int resCode = pthread_create(
            (kernelThreads + i), NULL, awaitTask, (void*)i
        );
        assert(0 == resCode);
    }
    scheduler();
#else
    __init_tempstack();
    uint32_t i = 0;
    uint8_t stillValid = 0;
    for (i = 0; i < g_threadManager->threadArrIndex; i++)
    {
        ThreadData* curThread = g_threadManager->threadArr[i];
        if (curThread->stillValid != 0 || curThread->curFuncAddr == 0)
        {
            stillValid = 1;
            callThreadFunc(curThread);
        }
        // This green thread has finished executing, and needs to be cleaned
        // up. Meaning, free all GC'd memory, and (TODO) remove from thread
        // list
        else
        {
            GC_Env* gcEnv = curThread->gcEnv;
            if (gcEnv != NULL)
            {
                __GC_free_all_allocs(gcEnv);
                free(gcEnv);
                curThread->gcEnv = NULL;
            }
        }
        if (i + 1 >= g_threadManager->threadArrIndex && stillValid != 0)
        {
            i = -1;
            stillValid = 0;
        }
    }
    __free_tempstack();
#endif
}

#ifdef MULTITHREAD

// Only execute this when you have the runtime_mutex locked!
static uint64_t scheduler_queue_full()
{
    uint64_t i;
    for (i = 0; i < numThreads; i++)
    {
        // If there is an empty slot, the queue isn't full
        if (schedulerData[i].valid == INVALID)
        {
            return 0;
        }
    }

    return 1;
}

// Only execute this when you have the runtime_mutex locked!
static uint64_t scheduler_queue_runnable()
{
    uint64_t i;
    for (i = 0; i < numThreads; i++)
    {
        if (schedulerData[i].valid == SCHEDULED)
        {
            return 1;
        }
    }

    return 0;
}

static uint64_t schedule_queue_count_valid()
{
    uint64_t i;
    uint64_t count = 0;
    for (i = 0; i < numThreads; i++)
    {
        if (schedulerData[i].valid != INVALID)
        {
            count++;
        }
    }

    return count;
}

// Either the thread is scheduled or running in the queue. When this is false,
// and while the runtime mutex is held, it is safe to inspect and modify the
// ThreadData object
static uint64_t thread_valid_in_queue(ThreadData* thread)
{
    uint64_t i;
    for (i = 0; i < numThreads; i++)
    {
        if (
            schedulerData[i].threadData == thread &&
            schedulerData[i].valid != INVALID
        ) {
            return 1;
        }
    }

    return 0;
}

// Return a valid index into the queue representing an empty slot, or a negative
// number
int64_t queue_empty_slot_index()
{
    uint64_t i;
    for (i = 0; i < numThreads; i++)
    {
        if (schedulerData[i].valid == INVALID) {
            return i;
        }
    }

    return -1;
}

// A simple queue-based scheduler that uses condition variables for signalling
// between the worker threads and the scheduler itself
void scheduler()
{
    uint64_t cur_gthread_index = 0;

    while (1)
    {
        pthread_mutex_lock(&runtime_mutex);

        // Wait while either the queue is full, or the queue contains all of the
        // available green threads
        while (
            scheduler_queue_full(schedulerData) != 0 ||
            (
                g_threadManager->threadArrIndex > 0 &&
                schedule_queue_count_valid() == g_threadManager->threadArrIndex
            )
        ) {
            pthread_cond_wait(cond_scheduler, &runtime_mutex);
        }

        if (g_threadManager->threadArrIndex == 0)
        {
            break;
        }

        uint64_t empty_slots = numThreads - schedule_queue_count_valid();

        uint64_t scheduled_gthreads = 0;
        uint64_t num_gthreads_tested = 0;

        while (
            g_threadManager->threadArrIndex > 0 &&
            scheduled_gthreads < empty_slots &&
            num_gthreads_tested < g_threadManager->threadArrIndex
        ) {
            // If we make it in here, we know that:
            //  - The queue is not full
            //  - There are green threads available to schedule

            if (cur_gthread_index >= g_threadManager->threadArrIndex)
            {
                cur_gthread_index = 0;
            }

            ThreadData* curThread =
                g_threadManager->threadArr[cur_gthread_index];

            num_gthreads_tested++;

            if (thread_valid_in_queue(curThread) != 0)
            {
                cur_gthread_index++;
                continue;
            }

            // If the green thread is schedulable, check to see if it's already
            // scheduled or if there's room to put it. If it's not already
            // scheduled, and there's somewhere to put it, put it there, and
            // notify the waiting threads of a new task
            if (curThread->stillValid != 0 || curThread->curFuncAddr == 0)
            {
                // If we make it in here, we know that:
                //  - The queue is not full
                //  - This green thread is not already either scheduled or
                //    running on the queue
                //  - This green thread is still active, and needs to be
                //    scheduled

                int64_t slot_index = queue_empty_slot_index();

                assert(slot_index >= 0);

                schedulerData[slot_index].threadData = curThread;
                schedulerData[slot_index].valid = SCHEDULED;

                scheduled_gthreads++;
            }
            // If the green thread is not schedulable, free it from the list
            else
            {
                deallocThreadData(curThread);

                // Replace this entry with the last entry in the list, if we're
                // not already at the end
                if (cur_gthread_index < g_threadManager->threadArrIndex - 1)
                {
                    g_threadManager->threadArr[
                        cur_gthread_index
                    ] = g_threadManager->threadArr[
                        g_threadManager->threadArrIndex - 1
                    ];
                }
                g_threadManager->threadArrIndex--;
            }

            cur_gthread_index++;
        }

        pthread_cond_broadcast(cond_workers);

        pthread_mutex_unlock(&runtime_mutex);
    }

    programDone = 1;

    pthread_cond_broadcast(cond_workers);

    pthread_mutex_unlock(&runtime_mutex);

    uint64_t i;
    for (i = 0; i < numThreads; i++)
    {
        pthread_join(kernelThreads[i], NULL);
    }

    // Reset programDone in case we restart the runtime
    programDone = 0;
}

void* awaitTask(void* arg)
{
    // Init the TLS tempstack used when dynamically growing the thread stack
    __init_tempstack();

    while (1)
    {
        pthread_mutex_lock(&runtime_mutex);

        while (
            scheduler_queue_runnable(schedulerData) == 0 &&
            programDone == 0
        ) {
            pthread_cond_wait(cond_workers, &runtime_mutex);
        }

        if (programDone != 0)
        {
            break;
        }

        uint64_t curThreadIndex;
        ThreadData* curThread = NULL;

        for (curThreadIndex = 0; curThreadIndex < numThreads; curThreadIndex++)
        {
            if (
                schedulerData[curThreadIndex].valid == SCHEDULED
            ) {
                curThread = schedulerData[curThreadIndex].threadData;
                schedulerData[curThreadIndex].valid = RUNNING;
                break;
            }
        }

        pthread_mutex_unlock(&runtime_mutex);

        if (curThread != NULL)
        {

            callThreadFunc(curThread);

            pthread_mutex_lock(&runtime_mutex);

            schedulerData[curThreadIndex].valid = INVALID;

            pthread_cond_signal(cond_scheduler);

            pthread_mutex_unlock(&runtime_mutex);
        }
    }

    pthread_mutex_unlock(&runtime_mutex);

    __free_tempstack();

    return NULL;
}

#endif
