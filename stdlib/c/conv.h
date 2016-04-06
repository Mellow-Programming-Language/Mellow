
#ifndef STD_C_CONV_H
#define STD_C_CONV_H

struct CString
{
    uint64_t markFunc;
    uint64_t dummy;
    const char* str;
};

void* cStringToString(struct CString* str);
struct CString* stringToCString(void* str);

#endif
