
#ifndef TLS_H
#define TLS_H

static __thread void* currentthread;
static __thread void* mainstack;
static __thread void* tempstack;

void* __get_tempstack();
void __init_tempstack();

void* get_currentthread();
void set_currentthread(void* val);

void* get_mainstack();
void set_mainstack(void* val);

#endif
