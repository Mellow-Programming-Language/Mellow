// This file contains both basic type hashing functions (int, string, etc.) and
// exposes the hash table backend implementation through wrapper functions.

#include <cstdint>
#include "hash.h"

uint64_t __mellow_hash_uint64(uint64_t key)
{
    // Algorithm credit: Thomas Wang
    key = (~key) + (key << 21); // key = (key << 21) - key - 1;
    key = key ^ (key >> 24);
    key = (key + (key << 3)) + (key << 8); // key * 265
    key = key ^ (key >> 14);
    key = (key + (key << 2)) + (key << 4); // key * 21
    key = key ^ (key >> 28);
    key = key + (key << 31);
    return key;
}

uint64_t __mellow_hash_string(char* string)
{
    uint64_t hash = 1;

    uint64_t pos = 1;

    for (int i = 0; 1; i++)
    {
        if (string[i] == 0)
            break;
        if ((string[i] & 7) == 0)
            hash *= 13 * pos;
        else if ((string[i] & 7) == 1)
            hash *= 3 * pos * pos;
        else if ((string[i] & 7) == 2)
            hash *= 27 * pos * pos * pos;
        else if ((string[i] & 7) == 3)
            hash *= 7 * pos * pos * pos * pos;
        else if ((string[i] & 7) == 4)
            hash *= 5 * pos * pos * pos * pos;
        else if ((string[i] & 7) == 5)
            hash *= 11 * pos * pos * pos;
        else if ((string[i] & 7) == 6)
            hash *= 37 * pos * pos;
        //else if (string[i] & 7 == 7)
        //    hash *= 91 * pos;
        else
        {
            hash *= pos;
            hash ^= 91909;
        }
        pos += 1;
    }
    return hash;
}
