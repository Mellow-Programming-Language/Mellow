#ifndef STDCONV_H
#define STDCONV_H

struct MaybeChar
{
    uint64_t runtimeData;
    uint64_t variantTag;
    char c;
};

int ord(char c);
void* chr(int c);
void* charToString(char c);
void* stringToChars(void* str);
void* charsToString(void* chs);

#endif
