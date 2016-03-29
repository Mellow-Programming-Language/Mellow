
const MELLOW_PTR_SIZE = 8; // sizeof(char*))
const MARK_FUNC_PTR = 8; // sizeof(void*))
// THe struct buffer bytes are simply so that the elements of the struct are
// aligned on an eight-byte boundary to begin with
const STRUCT_BUFFER_SIZE = 8; // sizeof(uint64_t))
const STR_SIZE = 8; // sizeof(uint64_t))
const CHAN_VALID_SIZE = 8; // sizeof(uint64_t))
const STR_START_OFFSET = MARK_FUNC_PTR + STR_SIZE;
const VARIANT_TAG_SIZE = 8; // sizeof(uint64_t))
const OBJ_HEAD_SIZE = MARK_FUNC_PTR + STRUCT_BUFFER_SIZE;
