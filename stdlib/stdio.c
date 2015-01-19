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

void* clam_fopen(void* str, struct FopenMode* mode)
{
    // Allocate space for a Maybe!File, which needs space for the ref-count, the
    // variant tag and space for the File ref in Some (File)
    void* maybeRes = malloc(REF_COUNT_SIZE + VARIANT_TAG_SIZE +
                            sizeof(struct ClamFile*));
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
        // Set ref-count to 1
        ((uint32_t*)maybeRes)[0] = 1;
        // Set tag to Some
        ((uint32_t*)maybeRes)[1] = 0;
        // The File ref lives just after the variant tag, which is four bytes
        ((struct ClamFile**)
            (maybeRes + REF_COUNT_SIZE + VARIANT_TAG_SIZE)
        )[0] = fileRef;
    }
    else
    {
        // Set ref-count to 1
        ((uint32_t*)maybeRes)[0] = 1;
        // Set tag to None
        ((uint32_t*)maybeRes)[1] = 1;
    }
    return maybeRes;
}

void clam_fclose(struct ClamFile* file)
{
    if (file->isOpen)
    {
        fclose(file->ptr);
        file->isOpen = 0;
    }
}
