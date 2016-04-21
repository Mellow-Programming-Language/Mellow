#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include "ptr_hashset.h"



// TESTING NONSENSE
static void printbin_rec(uint64_t b, int pos)
{
    if(pos == 64)
    {
        return;
    }


    printbin_rec(b>>1,pos+1);
    if((pos+1)%8 == 0)
    {
        //printf("pos:\t%d\n",pos);
        printf(" ");
    }

    printf("%d",(b&1) ? 1: 0);

}


// TESTING NONSENSE
static void printbin(uint64_t b)
{
    printbin_rec(b,0);
}

// Testing method to find the average length of a chain.
// Gives a measure of how many collisions there are in this hashset
static double avgChainLength(ptr_hashset_t *hashset)
{
    uint32_t nchains = 0;
    uint64_t totallength = 0;

    uint32_t i = 0;
    for(; i < hashset->_capacity; i++)
    {
        if(hashset->buckets[i] != NULL)
        {
            nchains++;
            key_node_t *chain = hashset->buckets[i];
            while(chain != NULL)
            {
                totallength++;
                chain = chain->next;
            }
        }
    }

    return (totallength) / (1.0*nchains);
}

// Calculates the longest chain in the hashset
// Mostly jst a curiosity thing. Even if a set has relatively many collisions,
// if the longest collision is only 2 entries (as was the case with one of my early tests),
// then we might not really care.
static uint64_t longestChain(ptr_hashset_t *hashset)
{
    uint64_t longest = 0;
    uint64_t curLength;

    int i = 0;
    for(; i < hashset->_capacity; i++)
    {
        if(hashset->buckets[i] != NULL)
        {
            curLength = 0;
            key_node_t *chain = hashset->buckets[i];
            while(chain != NULL)
            {
                curLength++;
                chain = chain->next;
            }
            // printf("%lu\n",curLength);
            if(curLength > longest)
            {
                longest = curLength;
            }
        }
    }

    return longest;
}



// Testing shit
static int num_free_manual(ptr_hashset_t *hashset)
{
    int count = 0;
    key_node_t *chain = hashset->free_nodes;
    while(chain  != NULL)
    {
        ++count;
        chain = chain->next;
    }
    return count;
}

// Testing shit?
static int trace(key_node_t *node)
{
    int len = 0;
    while(node != NULL)
    {
        len++;
        node = node->next;
    }
    return len;
}


// TESTING BULLSHIT
void test1(ptr_hashset_t *hashset)
{

    printf("Initial Capacity:\t%lu\n\n",hashset->_capacity);
    uint64_t val = 0;
    while(val < 800000)
    {
        add_key(hashset,(void*)val);
        val += 8;
    }

    char hasError = 0;
    val = 0;
    while(val < 800000)
    {
        if( ((val % 8) == 0) && !contains_key(hashset,(void*)val))
        {
            hasError = 1;
            printf("ERROR: Failed to find key:\t%lu\n",val);
        }
        else if(((val % 8) != 0) && contains_key(hashset,(void*)val))
        {
            hasError = 1;
            printf("ERROR: Found key in error:\t%lu\n",val);
            printf("Val %% 8 = %lu\n\n",val%8);
        }
        val++;
    }
    if(!hasError)
    {
        printf("Passed adding and contains test...\n\n");
    }

    printf("Longest chain:\n%lu\n",longestChain(hashset));
    printf("Average chain length:\n%lf\n",avgChainLength(hashset));
    printf("Capacity:\t%lu\nSize:\t\t%lu\n",hashset->_capacity,hashset->_num_entries);

    val = 0;
    while(val < 800000)
    {
        remove_key(hashset,(void*)val);
        val += 16;
    }


    hasError = 0;
    val = 0;
    while(val < 800000)
    {
        if(contains_key(hashset,(void*)val))
        {
            hasError = 1;
            printf("ERROR: Found key in error:\t%lu\n",val);
        }
        val += 8;
        if(!contains_key(hashset,(void*)val))
        {
            hasError = 1;
            printf("ERROR: Failed to find key:\t%lu\n",val);
        }
        val += 8;
    }
    if(!hasError)
    {
        printf("Passed removal test...\n\n");
    }

    printf("Longest chain:\n%lu\n",longestChain(hashset));
    printf("Average chain length:\n%lf\n",avgChainLength(hashset));
    printf("Capacity:\t%lu\nSize:\t\t%lu\n",hashset->_capacity,hashset->_num_entries);

    val = 0;
    while(val < 800000)
    {
        add_key(hashset,(void*)val);
        val += 8;
    }

    hasError = 0;
    val = 0;
    while(val < 800000)
    {
        if( ((val % 8) == 0) && !contains_key(hashset,(void*)val))
        {
            hasError = 1;
            printf("ERROR: Failed to find key:\t%lu\n",val);
        }
        else if(((val % 8) != 0) && contains_key(hashset,(void*)val))
        {
            hasError = 1;
            printf("ERROR: Found key in error:\t%lu\n",val);
            printf("Val %% 8 = %lu\n\n",val%8);
        }
        val++;
    }
    if(!hasError)
    {
        printf("Passed re-adding and contains test...\n\n");
    }


    printf("Longest chain:\n%lu\n",longestChain(hashset));
    printf("Average chain length:\n%lf\n",avgChainLength(hashset));
    printf("Capacity:\t%lu\nSize:\t\t%lu\n",hashset->_capacity,hashset->_num_entries);

}


int main(int argc, char **argv)
{

    ptr_hashset_t hashset;
    ptr_hashset_t *ptrset = &hashset;
    init_ptr_hashset(ptrset,10000);

    test1(ptrset);

    uint64_t val = 0;
    clock_t t_start, t_end;

    printf("Add...");
    t_start = clock();
    while(val < 10000000)
    {
        add_key(ptrset,(void*)val);
        val++;
    }
    t_end = clock();



    double diff = (double)(t_end - t_start) / CLOCKS_PER_SEC;

    // printf("%f\n%f\n%f\n",t_start,t_end,t_end - t_start);
    printf("%lf\n",diff);

    printf("Contains...\n");
    val = 0;
    t_start = clock();
    while(val < 10000000)
    {
        if(!contains_key(ptrset,(void*)val))
        {
            printf("ERROR\n");
        }
        val++;
    }
    t_end = clock();

    diff = (double)(t_end - t_start) / CLOCKS_PER_SEC;


    printf("Longest chain:\n%lu\n",longestChain(ptrset));
    printf("Average chain length:\n%lf\n",avgChainLength(ptrset));
    printf("Capacity:\t%lu\nSize:\t\t%lu\n",ptrset->_capacity,ptrset->_num_entries);

    // printf("%f\n%f\n%f\n",t_start,t_end,t_end - t_start);
    printf("%lf\n",diff);

    printf("Remove...\n");
    val = 0;
    t_start = clock();
    while(val < 10000000)
    {
        remove_key(ptrset,(void*)val);
        val++;
    }
    t_end = clock();

    diff = (double)(t_end - t_start) / CLOCKS_PER_SEC;

    // printf("%f\n%f\n%f\n",t_start,t_end,t_end - t_start);
    printf("%lf\n",diff);

    printf("Press any key...\n");
    getchar();
    destroy_ptr_hashset(ptrset);

    // uint32_t i;
    // uint64_t ptr  = 0;
    // uint32_t res;
    // for(i = 0; i < 1000000000; i++)
    // {
    //     res = rehash((void*)ptr);
    //     ptr++;
    // }

}
