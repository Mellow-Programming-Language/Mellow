
#include "gc.h"
#include "runtime_vars.h"
#include "scheduler.h"

GC_Env* __get_GC_Env()
{
#ifdef MULTITHREAD
    return get_currentthread()->gcEnv;
#else
    return currentthread->gcEnv;
#endif
}

ThreadData* __mellow_get_cur_green_thread()
{
#ifdef MULTITHREAD
    return get_currentthread();
#else
    return currentthread;
#endif
}
