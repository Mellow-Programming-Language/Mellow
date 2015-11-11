#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>
#include "stdio.h"
#include "mellow_internal.h"
#include "../runtime/runtime_vars.h"

void writeln(void* mellowStr)
{
    printf("%s\n", (char*)(mellowStr + HEAD_SIZE));
}

void write(void* mellowStr)
{
    printf("%s", (char*)(mellowStr + HEAD_SIZE));
}

void* readln()
{
    GC_Env* gc_env = __get_GC_Env();
    char* buffer = NULL;
    size_t len = 0;

    size_t bytesRead = getline(&buffer, &len, stdin);

    struct MaybeStr* str = (struct MaybeStr*)__GC_malloc(
        sizeof(struct MaybeStr),
        gc_env
    );
    str->refCount = 0;
    // Check if we outright failed to read a line, ie, EOF
    if (bytesRead == -1)
    {
        // Set tag to None
        str->variantTag = 1;
    }
    else
    {
        // Set tag to Some
        str->variantTag = 0;
        // The 1 is for space for the null byte
        void* mellowStr = __GC_malloc(
            HEAD_SIZE + bytesRead + 1,
            gc_env
        );
        // Set the ref count
        ((uint32_t*)mellowStr)[0] = 1;
        // Set the string length
        ((uint32_t*)mellowStr)[1] = bytesRead;
        memcpy(mellowStr + HEAD_SIZE, buffer, bytesRead + 1);
        free(buffer);
        str->str = mellowStr;
    }

    return str;
}

struct MaybeFile* mellow_fopen(void* str, struct FopenMode* mode)
{
    GC_Env* gc_env = __get_GC_Env();
    // Allocate space for a Maybe!File, which needs space for the ref-count, the
    // variant tag and space for the File ref in Some (File)
    struct MaybeFile* maybeFile =
        (struct MaybeFile*)__GC_malloc(sizeof(struct MaybeFile), gc_env);
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
        struct MellowFile* fileRef = (struct MellowFile*)__GC_malloc(
            sizeof(struct MellowFile),
            gc_env
        );
        fileRef->refCount = 1;
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
    // Set ref-count to 0
    maybeFile->refCount = 0;
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
    struct MaybeStr* str = (struct MaybeStr*)__GC_malloc(
        sizeof(struct MaybeStr),
        gc_env
    );
    str->refCount = 0;
    if (file->isOpen)
    {
        char* buffer = NULL;
        size_t linesize = 0;
        ssize_t bytesRead = getline(&buffer, &linesize, file->ptr);
        // Check if we outright failed to read a line, ie, EOF
        if (bytesRead == -1)
        {
            // Set tag to None
            str->variantTag = 1;
        }
        else
        {
            // Set tag to Some
            str->variantTag = 0;
            // The 1 is for space for the null byte
            void* mellowStr = __GC_malloc(
                HEAD_SIZE + bytesRead + 1,
                gc_env
            );
            // Set the ref count
            ((uint32_t*)mellowStr)[0] = 1;
            // Set the string length
            ((uint32_t*)mellowStr)[1] = bytesRead;
            memcpy(mellowStr + HEAD_SIZE, buffer, bytesRead + 1);
            free(buffer);
            str->str = mellowStr;
        }
    }
    else
    {
        // Set tag to None
        str->variantTag = 1;
    }
    return str;
}
