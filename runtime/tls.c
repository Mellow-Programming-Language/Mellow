
// This file is used to generate 'tls.asm'. 'tls.asm' is expected to be as bare
// as possible, as in not creating a stack frame or writing to any unnecessary
// registers. Since NASM does not document TLS well at all, GAS is used to
// assemble 'tls.asm' for linking back into 'callFunc.asm', and the runtime as
// a whole.

__thread void* currentthread;
__thread void* mainstack;

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
