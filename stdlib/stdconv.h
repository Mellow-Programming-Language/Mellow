#ifndef STDCONV_H
#define STDCONV_H

struct MaybeChar
{
    uint32_t refCount;
    uint32_t variantTag;
    char c;
};

int ord(char c);
void* chr(int c);
void* charToString(char c);

#endif
