
#ifndef RUNTIME_VARS_H
#define RUNTIME_VARS_H

#include "gc.h"
#include "scheduler.h"

#ifdef MULTITHREAD
extern ThreadData* get_currentthread();
#else
extern ThreadData* currentthread;
#endif

GC_Env* __get_GC_Env();

#endif
