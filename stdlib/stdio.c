#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>
#include "stdio.h"
#include "mellow_internal.h"
#include "../runtime/runtime_vars.h"

// (Mangled )GC marking functions we expect to exist at link time
extern void __mellow_GC_mark_S(void*);
extern void __mellow_GC_mark_V5Maybe1S(void*);
extern void __mellow_GC_mark_V5Maybe1R4File(void*);
extern void __mellow_GC_mark_R4File(void*);
extern void __mellow_GC_mark_V9FopenMode(void*);

void writeln(void* mellowStr)
{
    printf("%s\n", (char*)(mellowStr + HEAD_SIZE));
}

void write(void* mellowStr)
{
    printf("%s", (char*)(mellowStr + HEAD_SIZE));
}

struct MaybeStr* readln()
{
    GC_Env* gc_env = __get_GC_Env();
    char* buffer = NULL;
    size_t len = 0;

    size_t bytesRead = getline(&buffer, &len, stdin);

    struct MaybeStr* maybeStr = (struct MaybeStr*)__GC_malloc_nocollect(
        sizeof(struct MaybeStr),
        gc_env
    );
    maybeStr->markFunc = __mellow_GC_mark_V5Maybe1S;
    // Check if we outright failed to read a line, ie, EOF
    if (bytesRead == -1)
    {
        // Set tag to None
        maybeStr->variantTag = 1;
    }
    else
    {
        // Set tag to Some
        maybeStr->variantTag = 0;
        // The 1 is for space for the null byte
        void* mellowStr = __GC_malloc_nocollect(
            HEAD_SIZE + bytesRead + 1,
            gc_env
        );
        // Set the string marking function
        ((void**)mellowStr)[0] = __mellow_GC_mark_S;
        // Set the string length
        ((uint64_t*)mellowStr)[1] = bytesRead;
        memcpy(mellowStr + HEAD_SIZE, buffer, bytesRead + 1);
        free(buffer);
        maybeStr->str = mellowStr;
    }

    return maybeStr;
}

struct MaybeFile* mellow_fopen(void* str, struct FopenMode* mode)
{
    GC_Env* gc_env = __get_GC_Env();

    struct MaybeFile* maybeFile = (struct MaybeFile*)__GC_malloc_nocollect(
        sizeof(struct MaybeFile), gc_env
    );
    maybeFile->markFunc = __mellow_GC_mark_V5Maybe1R4File;
    FILE* file;
    switch (mode->mode)
    {
    case 0: file = fopen(str + HEAD_SIZE, "r");  break;
    case 1: file = fopen(str + HEAD_SIZE, "w");  break;
    case 2: file = fopen(str + HEAD_SIZE, "a");  break;
    case 3: file = fopen(str + HEAD_SIZE, "r+"); break;
    case 4: file = fopen(str + HEAD_SIZE, "w+"); break;
    case 5: file = fopen(str + HEAD_SIZE, "a+"); break;
    default:
        // It is a programming error to get here, as we are switching on the
        // possible variant tags
        assert(0);
    }
    if (file != NULL)
    {
        struct MellowFile* fileRef = (struct MellowFile*)__GC_malloc_nocollect(
            sizeof(struct MellowFile),
            gc_env
        );
        fileRef->markFunc = __mellow_GC_mark_R4File;
        fileRef->openMode = mode->mode;
        fileRef->ptr = file;
        fileRef->isOpen = 1;
        // Set tag to Some
        maybeFile->variantTag = 0;
        // The File ref lives just after the variant tag, which is four bytes
        maybeFile->ptr = fileRef;
    }
    else
    {
        // Set tag to None
        maybeFile->variantTag = 1;
    }
    maybeFile->markFunc = 0;
    return maybeFile;
}

void mellow_fclose(struct MellowFile* file)
{
    if (file->isOpen)
    {
        fclose(file->ptr);
        file->isOpen = 0;
    }
}

struct MaybeStr* mellow_freadln(struct MellowFile* file)
{
    GC_Env* gc_env = __get_GC_Env();
    struct MaybeStr* maybeStr = (struct MaybeStr*)__GC_malloc_nocollect(
        sizeof(struct MaybeStr),
        gc_env
    );
    maybeStr->markFunc = __mellow_GC_mark_V5Maybe1S;
    if (file->isOpen)
    {
        char* buffer = NULL;
        size_t linesize = 0;
        ssize_t bytesRead = getline(&buffer, &linesize, file->ptr);
        // Check if we outright failed to read a line, ie, EOF
        if (bytesRead == -1)
        {
            // Set tag to None
            maybeStr->variantTag = 1;
        }
        else
        {
            // Set tag to Some
            maybeStr->variantTag = 0;
            // The 1 is for space for the null byte
            void* mellowStr = __GC_malloc_nocollect(
                HEAD_SIZE + bytesRead + 1,
                gc_env
            );
            // Set the string marking function
            ((void**)mellowStr)[0] = __mellow_GC_mark_S;
            // Set the string length
            ((uint64_t*)mellowStr)[1] = bytesRead;
            memcpy(mellowStr + HEAD_SIZE, buffer, bytesRead + 1);
            free(buffer);
            maybeStr->str = mellowStr;
        }
    }
    else
    {
        // Set tag to None
        maybeStr->variantTag = 1;
    }
    return maybeStr;
}
