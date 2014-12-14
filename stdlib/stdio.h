#ifndef STDIO_H
#define STDIO_H

#include <stdint.h>
#include <stdio.h>

// clam-variant with 6 constructors:
// 0: read
// 1: write
// 2: append
// 3: read/update
// 4: write/update
// 5: append/update
struct FopenMode
{
    uint32_t refCount;
    uint32_t mode;
};

// clam-struct representing a file reference. This struct is declared as
// "extern struct File;" in stdio.clam
struct ClamFile
{
    uint32_t refCount;
    uint32_t openMode;
    FILE* ptr;
    unsigned char isOpen;
};

// Write a clam-string out to STDOUT
void clam_writeln(void* str);

// Return a Maybe!File for use with file operations
void* clam_fopen(void* str, struct FopenMode* mode);

// Given a File ref, close the file
// TODO: Must actually do something about the case of failure to close the file
void clam_fclose(struct ClamFile* file);

#endif
