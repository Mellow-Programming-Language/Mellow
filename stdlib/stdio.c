#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>
#include "stdio.h"
#include "clam_internal.h"

void writeln(void* clamStr)
{
    printf("%s\n", (char*)(clamStr + STR_START_OFFSET));
}

struct MaybeFile* clam_fopen(void* str, struct FopenMode* mode)
{
    // Allocate space for a Maybe!File, which needs space for the ref-count, the
    // variant tag and space for the File ref in Some (File)
    struct MaybeFile* maybeFile =
        (struct MaybeFile*)malloc(sizeof(struct MaybeFile));
    FILE* file;
    switch (mode->mode)
    {
    case 0: file = fopen(str + STR_START_OFFSET, "r");  break;
    case 1: file = fopen(str + STR_START_OFFSET, "w");  break;
    case 2: file = fopen(str + STR_START_OFFSET, "a");  break;
    case 3: file = fopen(str + STR_START_OFFSET, "r+"); break;
    case 4: file = fopen(str + STR_START_OFFSET, "w+"); break;
    case 5: file = fopen(str + STR_START_OFFSET, "a+"); break;
    default:
        // It is a programming error to get here, as we are switching on the
        // possible variant tags
        assert(0);
    }
    if (file != NULL)
    {
        struct ClamFile* fileRef = (struct ClamFile*)
                                   malloc(sizeof(struct ClamFile));
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

void clam_fclose(struct ClamFile* file)
{
    if (file->isOpen)
    {
        fclose(file->ptr);
        file->isOpen = 0;
    }
}
