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
