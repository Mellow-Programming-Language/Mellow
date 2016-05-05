

Object Memory Map
===

Every heap-allocated object in mellow is prefixed with a `16 B` "object header". The first `8 B` are always the address of a GC marking function. The first bit of the second  `8 B` is always a "mark bit", wherein a `0` means "unmarked", and a `1` means "marked." The remainder of the second `8 B` is reserved for use by the needs of that particular type.

Array
---

    [8 B GC Mark Func Ptr]         \
    [1 b GC Mark Bit:7 b Reserved]  |== 16 B Header
    [7 B Array Length]             /
    [N B Array Contents]

An array will always consume `16 B + sizeof(elem) * Array Length`. So:

    chars: []char = ['a', 'b', 'c'];

    [16 B][1 B char][1 B char][1 B char] == 19 B

    ints: []int = [1, 2, 3, 4];

    [16 B][4 B int][4 B int][4 B int][4 B int] == 32 B

    strings: []string = ["Hi!", "Hey!", "Hello!"];

    [16 B][8 B string][8 B string][8 B string] == 40 B

Associative Array
---

TBD.

Channel
---

    [8 B GC Mark Func Ptr]                          \
    [1 b GC Mark Bit:7 b Reserved]                   \
    [3 B Reserved]                                    |== 16 B Header
    [2 B mutex counter:1 B Reserved]                 /
    [7 b Reserved:1 b Contains Bit]                 /
    [N B Channel Contents]

The "Contains Bit" is set to `1` if the channel contains valid data that can be read. The Bit is then set to `0` when it is read, and stays `0` until the channel is written to, at which point it is switched back to `1`.

A channel object is only as large as it needs to be to house the type it channels between threads. So:

    chan!char   == [16 B][1 B char]   == 16 B
    chan!int    == [16 B][4 B int]    == 20 B
    chan!string == [16 B][8 B string] == 24 B

Function Pointer
---

    [8 B GC Mark Func Ptr]                                 \
    [1 b GC Mark Bit:1 b Has Environment Bit:6 b Reserved]  |== 16 B Header
    [7 B Reserved]                                         /
    [8 B Environment Ptr]
    [8 B Function Ptr]

The "Environment Bit" is set to `1` if the function pointer is actually a closure containing a context environment. Otherwise, the "Environment Bit" is set to `0`. Nothing will change the value of the "Environment Bit" for the duration of the lifetime of the function pointer.

If the "Environment Bit" is `0`, then simply the "Function Ptr" component is used when calling the function. If the "Environment Bit" is `1`, then the "Environment Ptr" is also passed in the invocation of the function, as though it were appended to the argument list of the function. That is, given a function that takes a single string as an argument, and where the first two argument-passing registers in x86 are RDI and RSI, the string is passed in RDI, and the "Environment Ptr" is passed in RSI. The actual code of the function itself will know that it is a closure that expects an "Environment Ptr" as an implicit final argument.

Set
---

TBD.

String
---

    [8 B GC Mark Func Ptr]         \
    [1 b GC Mark Bit:7 b Reserved]  |== 16 B Header
    [7 B String Length]            /
    [N B Characters][1 B Null ('\0')]

So:

    "Hello, world!" == [16 B][13 B "Hello, world!"][1 B '\0'] == 30 B

Struct
---

    [8 B GC Mark Func Ptr]         \
    [1 b GC Mark Bit:7 b Reserved]  |== 16 B Header
    [7 B Reserved]                 /
    [N B Struct Members]

The struct members will always be aligned, such that an `8 B` member is aligned to a multiple-of-8 address, a `4 B` member is aligned to a multiple-of-4 address, and a `2 B` member is aligned to a multiple-of-2 address. Where appropriate, unused memory will pad the space between members. The total size of the member-portion of the struct will be a multiple of the size of the largest member, so:

    struct Example {
        c1: char;
        c2: char;
        c3: char;
    }

    [16 B][1 B char][1 B char][1 B char] == 19 B

The members of the struct are contained in memory sequentially. Like in C, no automatic re-arranging of the members occurs to "pack" the members and reduce memory consumption of the struct object as a whole, so:

    struct Example {
        c: char;
        i: int;
        b: byte;
        s: string;
    }

    [16 B][1 B char][3 B pad][4 B int][1 B byte][7 B pad][8 B string] == 40 B

But, the members of the struct can be re-arranged in the struct definition itself to reduce memory consumption of the struct object:

    struct Example {
        i: int;
        c: char;
        b: byte;
        s: string;
    }

    [16 B][4 B int][1 B char][1 B byte][2 B pad][8 B string] == 32 B

Tuple
---

    [8 B GC Mark Func Ptr]         \
    [1 b GC Mark Bit:7 b Reserved]  |== 16 B Header
    [7 B Reserved]                 /
    [N B Tuple Contents]

The tuple members will always be aligned, such that an `8 B` member is aligned to a multiple-of-8 address, a `4 B` member is aligned to a multiple-of-4 address, and a `2 B` member is aligned to a multiple-of-2 address. Where appropriate, unused memory will pad the space between members.

    ('c', 1, "Hello!")

    [16 B][1 B char][3 B pad][4 B int][8 B string] == 32 B

Variant
---

    [8 B GC Mark Func Ptr]         \
    [1 b GC Mark Bit:7 b Reserved]  |== 16 B Header
    [5 B Reserved]                 /
    [2 B Variant Tag]             /
    [N B Variant Contents]

An object of a particular variant always consumes the same amount of memory, regardless of which constructor the variant currently is. The size of the variant will always be determined by the size of the largest constructor. If a variant contains no data-storing constructors, the variant object will only consume the `16 B` of the object header. For any constructor that does store data, the constructor members will always be aligned, such that an `8 B` member is aligned to a multiple-of-8 address, a `4 B` member is aligned to a multiple-of-4 address, and a `2 B` member is aligned to a multiple-of-2 address. Where appropriate, unused memory will pad the space between members.

    variant Example {
        Left (int, string),
        Right
    }

    test := Left(1, "Hello!");

    [16 B][4 B int][4 B pad][8 B string]

    test = Right;

    [16 B][16 B reserved]

But, a variant containing no data-storing constructors takes no more memory than the `16 B` required for the object header:

    variant Example {
        North,
        South,
        East,
        West
    }

    [16 B]
