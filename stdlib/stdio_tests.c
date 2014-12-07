#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "stdio.h"
#include "clam_internal.h"

void printClamStringInfo(void* clamStr)
{
    printf("Ref-count: %d\n", ((uint32_t*)clamStr)[0]);
    printf("Length   : %d\n", ((uint32_t*)clamStr)[1]);
}

int main(int argc, char** argv)
{
    void* testString = clam_allocString("Hello, world!", 13);
    printClamStringInfo(testString);
    clam_writeln(testString);
    clam_freeString(testString);
    return 0;
}
