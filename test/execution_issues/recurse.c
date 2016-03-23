
#include <stdio.h>

int recurse(int i)
{
    int j = i;
    if (i > 0)
    {
        j = i + recurse(i - 1);
    }
    return j;
}
