#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "stdio.h"
#include "mellow_internal.h"

void printMellowStringInfo(void* mellowStr)
{
    printf("Ref-count: %d\n", ((uint32_t*)mellowStr)[0]);
    printf("Length   : %d\n", ((uint32_t*)mellowStr)[1]);
}

int main(int argc, char** argv)
{
    void* testString = mellow_allocString("Hello, world!", 13);
    printMellowStringInfo(testString);
    writeln(testString);
    mellow_freeString(testString);
    return 0;
}
