/*
* I mean I'm not gonna claim this is a good idea...
*
*	Author: Darby Cairns <darby.cairns@gmail.com>
*
*/

#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include "ptr_hashset.h"

// Default load factor. Seems reasonable?
#define DEFAULT_LOAD_FACTOR 0.7;


// Default slab size
// I.E. when a hashset needs to grab more nodes to add entries, it will
// allocate DEFAULT_SLAB_SIZE such nodes at a time, to minimize malloc()
// calls and hopefully fragmentation?
#define DEFAULT_SLAB_SIZE (1<<12)


/*
* Just....get the number of entries currently in hashset.
*/
uint32_t get_size(ptr_hashset_t *hashset)
{
	// Do that thing I just said
	return hashset->_num_entries;
}

/*
* Frees a node by adding it to the free list
*
*/
static void free_node(ptr_hashset_t *hashset,key_node_t *node)
{
	node->next = hashset->free_nodes;
	hashset->free_nodes = node;
}


/*
* A secondary hash function to try to account for hashcodes which vary by
* constant multiples, and have little variance in lower bits.
*
* I wish I could just use Java's but that's GPL, so I had to jury-rig my own
* by trial and error. The bitshifting is intuitive, but the exact numbers were
* just experimentally determined.
*
* @param key
*    The key we're rehashing
*
* @return
*    The rehashed key, crushed into 32-bits
*
*/
static uint64_t rehash(void *key)
{
	// Make the key the kind of number I want it to be
	uint64_t i_key = (uint64_t)key;

	// Get the upper 32-bits of the key
	uint32_t hi_bits = (uint32_t)(i_key >> 32);

	// Get the lower 32-bits of the key
	uint32_t lo_bits = (uint32_t)(i_key);

	// hi_bits = (31 * hi_bits) ^ (61 * (hi_bits >> 16)) ^ (53 * (hi_bits >> 24));
	// lo_bits = (17 * lo_bits) ^ ( 37 * (lo_bits >> 16)) ^ ( 7 * (lo_bits >> 24)) ;
	
	// hi_bits = (31 * hi_bits) ^ (61 * (hi_bits >> 15)) ^ (53 * (hi_bits >> 23));
	// lo_bits = (17 * lo_bits) ^ ( 37 * (lo_bits >> 15)) ^ ( 7 * (lo_bits >> 23)) ;

	hi_bits ^= ((hi_bits >> 15)) ^ ((hi_bits >> 23));
	hi_bits ^= (hi_bits >> 7) ^ (hi_bits >> 5);

	lo_bits ^= ((lo_bits >> 15)) ^ ((lo_bits >> 23)) ;
	lo_bits ^= (lo_bits >> 7) ^ (lo_bits >> 5);

	return  (i_key & 0xffffffff00000000L ) | ((hi_bits) ^ (lo_bits));

}

/*
* Initialized the hashset pointed to by <hashset>
*
* @param hashset
*    The hashset we're initializing
*
* @param init_size
*    Essentially a hint for the number of elements you expect to add to this hashset.
*    This is intended to minimize the number of times resize() is called.
*    In practice, normally at least one resize will be triggered since the capacity
*    is set to the nearest power of 2 greater than init_size, but the load factor can
*    mess things up.
*
*/
void init_ptr_hashset(ptr_hashset_t *hashset,size_t init_size)
{
		// Set the capacity yo hold at least init_size things
		// note that load factor can mean a resize will happen even
		// if no more than init_size things are ever added.
		hashset->_capacity = 1 << (int)(ceil(log2(init_size)));

		// Initialize the backing array for this hashset
		hashset->buckets = calloc(hashset->_capacity, sizeof(key_node_t *));

		// We start off empty
		hashset->_num_entries = 0;
		
		// Right now we're just going with default values for these, but
		// there's the option to change that later.
		hashset->_load_factor = DEFAULT_LOAD_FACTOR;
		hashset->_slab_size =  DEFAULT_SLAB_SIZE;

		// Start off with just one slab of free nodes
		hashset->key_node_slab_list = (node_slab_list_t*)malloc(sizeof(node_slab_list_t));

		// Our slab list has only one entry to start
		hashset->key_node_slab_list->next = NULL;

		// Allocate a slab of free nodes to start with
		hashset->key_node_slab_list->slab = (key_node_t*)malloc( hashset->_slab_size * sizeof(key_node_t));

		// Null-terminate the free list
		hashset->free_nodes = NULL;

		// Add all the nodes in the slab we just allocated to the free list.
		// Done in reverse order so they will be grabbed sequentially, but that's
		// likely not important at all.
		int i = (hashset->_slab_size) - 1;
		for(; i >= 0; i--)
		{
			free_node(hashset, (hashset->key_node_slab_list->slab) + i );
		}
}

/*
* Frees all memory in use by the given ptr_hashset_t
*
* @param hashset
*    The hashset we're destroying
*
*/
void destroy_ptr_hashset(ptr_hashset_t * hashset)
{
	// Free the backing array
	free(hashset->buckets);

	// Walk through the slab list and free all the slabs, as well as the 
	// nodes in the slab list, which were themselves allocated with malloc
	node_slab_list_t *trace = hashset->key_node_slab_list;
	node_slab_list_t *prev_trace;
	while(trace != NULL)
	{
		free(trace->slab);
		prev_trace = trace;
		trace = trace->next;
		free(prev_trace);
	}

	//free(hashset->key_node_slab);
}

// Forward declaration of resize
static int resize(ptr_hashset_t *hashset);

/*
*
* Okay but I'm chainging this in a minute though
*
*/
static int alloc_node_slab(ptr_hashset_t *hashset)
{
	// I should realy just stick this at the beginning of the larger allocation
	// and treat it like a header dealie.
	// Good enough for now though.
	node_slab_list_t *newSlab = (node_slab_list_t *)malloc(sizeof(node_slab_list_t));
	if(newSlab == NULL)
	{
		return 1;
	}
	newSlab->slab = (key_node_t*)malloc(sizeof(key_node_t) * hashset->_slab_size);
	if((newSlab->slab) == NULL)
	{
		free(newSlab);
		return 1;
	}
	newSlab->next = hashset->key_node_slab_list;
	hashset->key_node_slab_list = newSlab;

	int i = (hashset->_slab_size)-1;
	for(; i >= 0; i--)
	{
		free_node(hashset, (newSlab->slab) + i);
	}
	return 0;
}

/*
* Allocate a node from the free list to hold data
*/
static key_node_t *alloc_node(ptr_hashset_t *hashset)
{
	// If our free list is empty, attempt to allocate more
	// nodes to use. If we can't do that, we're fucked.
	if(hashset->free_nodes == NULL)
	{
		if(alloc_node_slab(hashset))
		{
			return NULL;
		}
	}

 	// Grab the head of the free list to return
	key_node_t *retNode = hashset->free_nodes;
	hashset->free_nodes = retNode->next;

	// This node has to have next be NULL in so that it can be safely
	// added to a chain in the backing array
	retNode->next = NULL;
	return retNode;
}

/*
* Adds the given node to the hashset. This is called by the add_key
* function, and the user should never interact with it.
*
* If this function fails due to not being able to allocate enough memory,
* it breaks everything. Because it should?
*
* Note that I should probably do the resize thing before adding the node
* if adding the node would cause a resize to occur.
* But I didn't.
*
* @param hashset
*    The hashset we're adding to
* 
* @param node
*    The node (containing the key) we're adding to this hashset
*
*
* @return 
*    0 If this node was successfully added, 1 if the add operation failed
*    (Because the key was already in the set)
*/
static char add_node(ptr_hashset_t *hashset, key_node_t *node)
{
	// Find the index this key lives at
	uint64_t index = ( rehash(node->key) ) & ((hashset->_capacity) - 1);
	key_node_t * chain = (hashset->buckets)[index];

	// If this bucket it empty, put the node into it, and return 0
	// to indicate a successful addition
	if(chain == NULL)
	{
		(hashset->buckets [index]) = node;
		hashset->_num_entries++;
		// If adding this node put us over our load factor, resize the whole bitch.
		if( ((hashset->_num_entries * 1.0) / hashset->_capacity)  >= hashset->_load_factor)
		{
			int ret = resize(hashset);
			if(ret)
			{
				perror("Hashset failed to allocate memory during resize operation.\n");
				exit(1);
			}
		}
		return 0;
	}

	key_node_t *prev_chain;
	while(chain != NULL)
	{
		// If this node has the same key as what we're trying to add,
		// return 1 to indicate this key was already in the set
		if((chain->key) == (node->key) )
		{
			return 1;
		}
		prev_chain = chain;
		chain = chain->next;
	}

	// Append the node to the chain in this bucket, and return 0 to
	// indiciate a successful addition
	prev_chain->next = node;
	hashset->_num_entries++;
	// Resize if we need to
	if( ((hashset->_num_entries * 1.0) / hashset->_capacity)  >= hashset->_load_factor)
	{
		int ret = resize(hashset);
		if(ret)
		{
			perror("Hashset failed to allocate memory during resize operation.\n");
			exit(1);
		}
	}
	return 0;
}

/*
* Add the given key to this hashset
*
*
* @param hashset
*    The hashset we're adding to
*
* @param key
*    The key to add to this hashset
*
*
* @return
*    0 if the key was added successfully, 1 if this key was already in the set 
*/
char add_key(ptr_hashset_t *hashset, void *key)
{
	// If this fails we've got problems
	key_node_t *newNode = alloc_node(hashset);

	newNode->key = key;
	int ret = add_node(hashset,newNode);
	if(ret)
	{
		free_node(hashset, newNode);
	}
	return ret;
}




/*
* Removes the given key from this set, if it is contained in the set
*
*
* @param key
*		The key we want to remove
*
* @return
*		0 if the key was successfully removed, 1 if the key was not found in the set
*
*/
char remove_key(ptr_hashset_t *hashset, void *key)
{
	
	// Calculate index in array
	uint64_t index = ( rehash(key) ) & ((hashset->_capacity) - 1);
	key_node_t * chain = (hashset->buckets)[index];

	// If this bucket is empty, return 1 to indicate nothing was removed
	if(chain == NULL)
	{
		return 1;
	}

	key_node_t *prev_chain = NULL;
	while(chain != NULL)
	{
		
		// If this node has the same key as what we're trying to remove,
		// remove it, and return 0 to indicate something was removed
		if((chain->key) == (key) )
		{
			if(prev_chain == NULL)
			{
				(hashset->buckets)[index] = chain->next;
			}
			else
			{
				prev_chain->next = chain->next;
			}
			// Free this node
			free_node(hashset,chain);
			hashset->_num_entries--;
			return 0;
		}
		prev_chain = chain;
		chain = chain->next;
	}
	

	// If we reach here, we didn't find it
	return 1;	
}


/*
* Checks whether the given key is contained in this hashset
*
* @param key
*		The key we're looking for
*
* @return
*		1 if the key is contained in this set, 0 if not
*
*/
char contains_key(ptr_hashset_t *hashset, void *key)
{
	uint64_t index = ( rehash(key) ) & ((hashset->_capacity) - 1);
	key_node_t * chain = (hashset->buckets)[index];

	// If this bucket it empty, we definitely don't have this key
	if(chain == NULL)
	{
		return 0;
	}

	// Should be do-while but....meh
	while(chain != NULL)
	{
		// If this node has the key we're looking for, return true
		if((chain->key) == (key) )
		{
			return 1;
		}
		chain = chain->next;
	}

	// If we reach here, we don't have this key
	return 0;
}


/*
* This is called to resize the hashset structure when we exceed the load factor
*
* @param hashset
*    The hashset to resize
*
* @return
*    0 on success, 1 on failure (failure here probably means an exit() call)
*
*/
static int resize(ptr_hashset_t *hashset)
{
	// static count = 1;
	// printf("Resize triggered...\n");

	uint32_t old_cap = hashset->_capacity;

	// Double the capacity. This exponential growth yields amortized constant time for
	// add operations.
	// Some people do 1.5x growth, but then I'd have to change the index calculation,
	// and also screw it.
	hashset->_capacity <<= 1;

	// We need to gather a list of all the entries currently in the hashet to re-add once
	// we've resized everything
	key_node_t *addList = NULL;
	uint32_t bucket_itr;

	// Find first non-empty bucket to give initial value to addList
	for(bucket_itr = 0; bucket_itr < old_cap; bucket_itr++)
	{
		if((hashset->buckets)[bucket_itr] != NULL)
		{
			addList = (hashset->buckets)[bucket_itr];
			bucket_itr++;
			break;
		}
	}

	key_node_t *chain = NULL;
	key_node_t *prev_chain = NULL;

	// Now finish building addList
	for(;bucket_itr < old_cap; bucket_itr++)
	{
		chain = (hashset->buckets)[bucket_itr];

		// If this bucket isn't empty
		if(chain != NULL)
		{
			// Find the end of the chain living in this bucket
			do
			{
				prev_chain = chain;
				chain = chain->next;
			} while(chain != NULL);

			// And put this chain on the addList
			prev_chain->next = addList;
			addList = (hashset->buckets)[bucket_itr];
		}
	}


	// Free the old backing array
	free(hashset->buckets);

	// Allocate and zero-out a new backing array
	hashset->buckets = (key_node_t **)calloc(hashset->_capacity, 
											sizeof(key_node_t *) );
	
	// If that didn't work, we need to go home. We need to go home and go to bed.
	if(hashset->buckets == NULL)
	{
		return 1;
	}

	// We increment this add, and it would be dumb to write a special-purpose resize
	// add operation as far as I'm concerned, so we'll just zero this and let add recover it
	hashset->_num_entries = 0;


	// Add everything on the addList we built (all the node which had
	// been in this hashset prior to this resize).
	key_node_t *nxt;
	while(addList != NULL)
	{
		nxt = addList->next;
		addList->next = NULL;
		add_node(hashset,addList);
		addList = nxt;
	}


	// printf("Resize completed...%d\n",count++);
	return 0;
}
