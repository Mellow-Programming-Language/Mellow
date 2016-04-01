#ifndef STDIO_H
#define STDIO_H

#include <stdint.h>
#include <stdio.h>

// mellow-variant with 6 constructors:
// 0: read
// 1: write
// 2: append
// 3: read/update
// 4: write/update
// 5: append/update
struct FopenMode
{
    void* markFunc;
    uint64_t mode;
};

// mellow-struct representing a file reference. This struct is declared as
// "extern struct File;" in stdio.mlo
struct MellowFile
{
    void* markFunc;
    uint64_t openMode;
    FILE* ptr;
    unsigned char isOpen;
};

struct MaybeFile
{
    void* markFunc;
    uint64_t variantTag;
    struct MellowFile* ptr;
};

struct MaybeStr
{
    void* markFunc;
    uint64_t variantTag;
    void* str;
};

// Write a mellow-string out to STDOUT
void writeln(void* str);
void write(void* str);
// Read a mellow-string from STDIN
struct MaybeStr* readln();

// Return a Maybe!File for use with file operations
struct MaybeFile* mellow_fopen(void* str, struct FopenMode* mode);

// Given a File ref, close the file
// TODO: Must actually do something about the case of failure to close the file
void mellow_fclose(struct MellowFile* file);

struct MaybeStr* mellow_freadln(struct MellowFile* file);

#endif
