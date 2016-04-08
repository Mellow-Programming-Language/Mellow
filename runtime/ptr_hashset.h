#ifndef PTR_HASHSET_H
#define PTR_HASHSET_H

// Simple singly-linked list style node for chaining method of bucket storage
typedef struct keyNode
{
	// The key stored in this node (as this is a set, also the value)
	void *key;

	// The next node in this linked list (NULL if final node)
	struct keyNode *next;

}key_node_t;


/*
* Structure to form a linked-list of arrays (slabs) or key_note_t structures.
* Used for a bastardized suballocator because I felt like that was a good idea?
*/
typedef struct nodeSlabList
{

	// The pointer to the start of the memory slab this node is keeping track of.
	// The size is known based on the value of _slab_size in the ptr_hashset_t which
	// owns this node_slab_list_t
	key_node_t *slab;

	// The next entry in our linked-list of memory slabs (NULL if final node)
	struct nodeSlabList *next;

}node_slab_list_t;



typedef struct _ptr_hashset_t
{
	// The internal storage array which backs this hashset
	key_node_t **buckets;

	// The size of buckets
	uint64_t _capacity;

	// The actual number of entries currently stored in this hashset.
	uint64_t _num_entries;

	// Slab of memory from which to suballocate key_node_t's.
	// Gonna be a dirt stupid suballocator though
	node_slab_list_t *key_node_slab_list;
	
	
	// This is the size of the slab we grab when we run out of free nodes.
	// Essentially, when we need new nodes, we allocate _slab_size nodes all
	// at once, so we can try to minimize head fragmentation and malloc calls.
	// Kind of, anyway.
	uint32_t _slab_size;
	
	// Linked List of free nodes to pull from
	key_node_t *free_nodes;
	
	/*
	* The load factor for this hashset.
	*
	* I.E. once the hashset contains (_load_factor * capacity) entries,
	* a resize operation is performed
	*/
	double _load_factor;
}ptr_hashset_t;


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
void init_ptr_hashset(ptr_hashset_t *hashset,size_t init_size);

/*
* Frees all memory in use by the given ptr_hashset_t
*
* @param hashset
*    The hashset we're destroying
*
*/
void destroy_ptr_hashset(ptr_hashset_t * hashset);


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
char add_key(ptr_hashset_t *hashset, void *key);

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
char remove_key(ptr_hashset_t *hashset, void *key);

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
char contains_key(ptr_hashset_t *hashset, void *key);

/*
* Just....get the number of entries currently in hashset.
*/
uint32_t get_size(ptr_hashset_t *hashset);

#endif