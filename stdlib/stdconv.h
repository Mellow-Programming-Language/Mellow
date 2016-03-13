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
uint32_t byteToInt(uint8_t in);
uint8_t intToByte(uint32_t in);
void* charToString(char c);
void* stringToChars(void* str);
void* charsToString(void* chs);

#endif
