import std.stdio;
import std.algorithm;
import std.range;
import std.conv;
import parser;

const PTR_SIZE = 8;
const FAT_PTR_SIZE = 16;

enum TypeEnum
{
    VOID,
    LONG,
    INT,
    SHORT,
    BYTE,
    FLOAT,
    DOUBLE,
    CHAR,
    BOOL,
    STRING,
    SET,
    HASH,
    ARRAY,
    AGGREGATE,
    TUPLE,
    FUNCPTR,
    STRUCT,
    VARIANT,
    CHAN,
}

struct ArrayType
{
    Type* arrayType;

    ArrayType* copy()
    {
        auto c = new ArrayType();
        c.arrayType = this.arrayType.copy;
        return c;
    }

    string format() const
    {
        return "[]" ~ arrayType.format();
    }

    string formatMangle() const
    {
        return "@A" ~ arrayType.formatMangle();
    }
}

struct HashType
{
    Type* keyType;
    Type* valueType;

    HashType* copy()
    {
        auto c = new HashType();
        c.keyType = this.keyType.copy;
        c.valueType = this.valueType.copy;
        return c;
    }

    string format() const
    {
        return "[" ~ keyType.format() ~ "]" ~ valueType.format();
    }

    string formatMangle() const
    {
        return "@K" ~ keyType.formatMangle()
             ~ "@N" ~ valueType.formatMangle();
    }
}

struct SetType
{
    Type* setType;

    SetType* copy()
    {
        auto c = new SetType();
        c.setType = this.setType.copy;
        return c;
    }

    string format() const
    {
        return "<>" ~ setType.format();
    }

    string formatMangle() const
    {
        return "@S" ~ setType.formatMangle();
    }
}

struct AggregateType
{
    string typeName;
    Type*[] templateInstantiations;

    AggregateType* copy()
    {
        auto c = new AggregateType();
        c.typeName = this.typeName;
        c.templateInstantiations = this.templateInstantiations
                                       .map!(a => a.copy)
                                       .array;
        return c;
    }

    string format() const
    {
        string str = typeName;
        if (templateInstantiations.length == 1)
        {
            str ~= "!" ~ templateInstantiations[0].format();
        }
        else if (templateInstantiations.length > 1)
        {
            str ~= "!(" ~ templateInstantiations.map!(a => a.format())
                                                .join(", ");
            str ~= ")";
        }
        return str;
    }

    string formatMangle() const
    {
        return "@Z" ~ typeName;
    }
}

struct TupleType
{
    Type*[] types;

    TupleType* copy()
    {
        auto c = new TupleType();
        c.types = this.types
                      .map!(a => a.copy)
                      .array;
        return c;
    }

    string format() const
    {
        return "(" ~ types.map!(a => a.format()).join(", ") ~ ")";
    }

    string formatMangle() const
    {
        auto str = "";
        str ~= "@T" ~ types.length.to!string;
        foreach (type; types)
        {
            str ~= type.formatMangle();
        }
        return str;
    }
}

// Type representing the value that is a callable function pointer. Note that
// all function pointers are fat pointers, though they may not necessarily be
// actual closures
struct FuncPtrType
{
    // The types of the arguments to the function, in the order they appeared
    // in the original argument list
    Type*[] funcArgs;
    // Even if the return type is a tuple, it's still really only a single type
    Type* returnType;

    FuncPtrType* copy()
    {
        auto c = new FuncPtrType();
        c.returnType = this.returnType.copy;
        c.funcArgs = this.funcArgs
                         .map!(a => a.copy)
                         .array;
        return c;
    }

    // The syntax for function pointers is not yet decided, so this is temporary
    string format() const
    {
        string str = "";
        str ~= "fn (";
        if (funcArgs.length > 0)
        {
            str ~= funcArgs.map!(a => a.format()).join(", ");
        }
        str ~= ")";
        if (returnType.tag != TypeEnum.VOID)
        {
            str ~= " => " ~ returnType.format();
        }
        return str;
    }

    string formatMangle() const
    {
        auto str = "";
        str ~= "@F" ~ funcArgs.length.to!string;
        foreach (type; funcArgs)
        {
            str ~= type.formatMangle();
        }
        str ~= "@Y" ~ returnType.formatMangle();
        return str;
    }
}

struct StructMember
{
    string name;
    Type* type;

    StructMember copy()
    {
        auto c = StructMember();
        c.name = this.name;
        c.type = this.type.copy;
        return c;
    }

    string format() const
    {
        return name ~ ": " ~ type.format() ~ ";";
    }

    auto size()
    {
        return type.size();
    }
}

struct StructType
{
    string name;
    string[] templateParams;
    StructMember[] members;
    bool isExtern;
    bool instantiated;
    Type*[string] mappings;

    StructType* copy()
    {
        auto c = new StructType();
        c.name = this.name;
        c.templateParams = this.templateParams;
        c.members = this.members
                        .map!(a => a.copy)
                        .array;
        c.isExtern = this.isExtern;
        c.instantiated = this.instantiated;
        c.mappings = this.mappings;
        return c;
    }

    string formatFull() const
    {
        string str = "";
        if (isExtern)
        {
            str ~= "extern ";
        }
        str ~= "struct " ~ name;
        if (templateParams.length > 0)
        {
            if (instantiated)
            {
                str ~= "!(";
                str ~= templateParams.map!(a => a ~ "=" ~ mappings[a].format)
                                     .join(", ");
                str ~= ")";
            }
            else
            {
                str ~= "(" ~ templateParams.join(", ") ~ ")";
            }
        }
        if (isExtern)
        {
            str ~= ";";
        }
        else
        {
            str ~= " {\n";
            foreach (member; members)
            {
                str ~= "    " ~ member.format() ~ "\n";
            }
            str ~=  "}";
        }
        return str;
    }

    string format() const
    {
        string str = "";
        str ~= name;
        if (templateParams.length > 0)
        {
            if (instantiated)
            {
                str ~= "!(";
                str ~= templateParams.map!(a => a ~ "=" ~ mappings[a].format)
                                     .join(", ");
                str ~= ")";
            }
            else
            {
                str ~= "(" ~ templateParams.join(", ") ~ ")";
            }
        }
        return str;
    }

    string formatMangle() const
    {
        auto str = "";
        str ~= "@R" ~ name;
        foreach (param; templateParams)
        {
            str ~= mappings[param].formatMangle();
        }
        return str;
    }

    // The size of the struct on the heap is the total aligned size of all the
    // members
    auto size()
    {
        return members.map!(a => a.size)
                      .array
                      .getAlignedSize;
    }

    auto getMember(string memberName)
    {
        foreach (i, member; members)
        {
            if (member.name == memberName)
            {
                return member;
            }
        }
        assert(false, "Unreachable");
    }

    auto getOffsetOfMember(string memberName)
    {
        int[] memberSizes;
        foreach (i, member; members)
        {
            memberSizes ~= member.type.size;
            if (member.name == memberName)
            {
                return getAlignedIndexOffset(memberSizes, i);
            }
        }
        assert(false, "Unreachable");
    }
}

struct VariantMember
{
    string constructorName;
    // Intended to be a tuple
    Type* constructorElems;

    VariantMember copy()
    {
        // In order to solve the recurse-forever copy() bug, we need to
        // be sure to transform any references to a variant type _back_ to
        // an aggregate placeholder. Variant types are the only types that
        // can be recursive, as it's not possible to write down the
        // instantiation of a struct that contains itself as a member, but
        // variant types can be written that way (as an instantiation of such
        // a type necessitates the existence of a base variant constructor).
        // So, for any VariantType value, transform it back into an aggregate
        // placeholder of that type, otherwise just make a straight copy
        auto c = VariantMember();
        c.constructorName = this.constructorName;
        if (this.constructorElems.tag == TypeEnum.TUPLE)
        {
            auto wrap = new Type();
            wrap.tag = TypeEnum.TUPLE;
            wrap.tuple = new TupleType();
            Type*[] tupleCopy;
            foreach (elem; this.constructorElems.tuple.types)
            {
                if (elem.tag == TypeEnum.VARIANT)
                {
                    auto agg = new Type();
                    agg.tag = TypeEnum.AGGREGATE;
                    agg.aggregate = new AggregateType();
                    agg.aggregate.typeName = elem.variantDef.name;
                    if (elem.variantDef.instantiated)
                    {
                        foreach (key; elem.variantDef.templateParams)
                        {
                            agg.aggregate.templateInstantiations ~=
                                elem.variantDef.mappings[key];
                        }
                    }
                    tupleCopy ~= agg;
                }
                else
                {
                    tupleCopy ~= elem.copy;
                }
            }
            wrap.tuple.types = tupleCopy;
            c.constructorElems = wrap;
        }
        else
        {
            c.constructorElems = this.constructorElems.copy;
        }
        return c;
    }

    string format() const
    {
        string str = "";
        str ~= constructorName;
        if (constructorElems.tag != TypeEnum.VOID)
        {
            str ~= constructorElems.format();
        }
        return str;
    }

    auto size()
    {
        return constructorElems.size();
    }
}

struct VariantType
{
    string name;
    string[] templateParams;
    VariantMember[] members;
    bool instantiated;
    Type*[string] mappings;

    VariantType* copy()
    {
        auto c = new VariantType();
        c.name = this.name;
        c.templateParams = this.templateParams;
        c.members = this.members
                        .map!(a => a.copy)
                        .array;
        c.instantiated = this.instantiated;
        c.mappings = this.mappings;
        return c;
    }

    string formatFull() const
    {
        string str = "";
        str ~= "variant " ~ name;
        if (templateParams.length > 0)
        {
            if (instantiated)
            {
                str ~= "!(";
                str ~= templateParams.map!(a => a ~ "=" ~ mappings[a].format)
                                     .join(", ");
                str ~= ")";
            }
            else
            {
                str ~= "(" ~ templateParams.join(", ") ~ ")";
            }
        }
        str ~= " {\n";
        foreach (member; members)
        {
            str ~= "    " ~ member.format() ~ "\n";
        }
        str ~= "}";
        return str;
    }

    string format() const
    {
        string str = "";
        str ~= name;
        if (templateParams.length > 0)
        {
            if (instantiated)
            {
                str ~= "!(";
                str ~= templateParams.map!(a => a ~ "=" ~ mappings[a].format)
                                     .join(", ");
                str ~= ")";
            }
            else
            {
                str ~= "(" ~ templateParams.join(", ") ~ ")";
            }
        }
        return str;
    }

    string formatMangle() const
    {
        auto str = "";
        str ~= "@V" ~ name;
        foreach (param; templateParams)
        {
            str ~= mappings[param].formatMangle();
        }
        return str;
    }

    // The total size of a variant value on the heap is the size of the largest
    // constructor
    auto size()
    {
        return members.map!(a => a.size)
                      .reduce!(max);
    }

    auto isMember(string memberName)
    {
        foreach (member; members)
        {
            if (member.constructorName == memberName)
            {
                return true;
            }
        }
        return false;
    }

    auto getMember(string memberName)
    {
        foreach (member; members)
        {
            if (member.constructorName == memberName)
            {
                return member;
            }
        }
        assert(false, "Unreachable");
    }

    auto getMemberIndex(string memberName)
    {
        foreach (i, member; members)
        {
            if (member.constructorName == memberName)
            {
                return i;
            }
        }
        assert(false, "Unreachable");
    }
}

struct ChanType
{
    Type* chanType;

    ChanType* copy()
    {
        auto c = new ChanType();
        c.chanType = this.chanType.copy;
        return c;
    }

    string format() const
    {
        return "chan!(" ~ chanType.format() ~ ")";
    }

    string formatMangle() const
    {
        return "@C" ~ chanType.formatMangle();
    }
}

struct Type
{
    TypeEnum tag;
    bool constType;
    union {
        ArrayType* array;
        HashType* hash;
        SetType* set;
        AggregateType* aggregate;
        TupleType* tuple;
        FuncPtrType* funcPtr;
        StructType* structDef;
        VariantType* variantDef;
        ChanType* chan;
    };

    Type* copy()
    {
        auto c = new Type();
        c.tag = this.tag;
        c.constType = this.constType;
        final switch (tag)
        {
        case TypeEnum.VOID:
        case TypeEnum.LONG:
        case TypeEnum.INT:
        case TypeEnum.SHORT:
        case TypeEnum.BYTE:
        case TypeEnum.FLOAT:
        case TypeEnum.DOUBLE:
        case TypeEnum.CHAR:
        case TypeEnum.BOOL:
        case TypeEnum.STRING:
            break;
        case TypeEnum.SET:
            c.set = this.set.copy;
            break;
        case TypeEnum.HASH:
            c.hash = this.hash.copy;
            break;
        case TypeEnum.ARRAY:
            c.array = this.array.copy;
            break;
        case TypeEnum.TUPLE:
            c.tuple = this.tuple.copy;
            break;
        case TypeEnum.FUNCPTR:
            c.funcPtr = this.funcPtr.copy;
            break;
        case TypeEnum.STRUCT:
            c.structDef = this.structDef.copy;
            break;
        case TypeEnum.VARIANT:
            c.variantDef = this.variantDef.copy;
            break;
        case TypeEnum.AGGREGATE:
            c.aggregate = this.aggregate.copy;
            break;
        case TypeEnum.CHAN:
            c.chan = this.chan.copy;
            break;
        }
        return c;
    }

    string format() const
    {
        string str = "";
        if (constType)
        {
            str ~= "const ";
        }
        final switch (tag)
        {
        case TypeEnum.VOID      : return str ~ "void";
        case TypeEnum.LONG      : return str ~ "long";
        case TypeEnum.INT       : return str ~ "int";
        case TypeEnum.SHORT     : return str ~ "short";
        case TypeEnum.BYTE      : return str ~ "byte";
        case TypeEnum.FLOAT     : return str ~ "float";
        case TypeEnum.DOUBLE    : return str ~ "double";
        case TypeEnum.CHAR      : return str ~ "char";
        case TypeEnum.BOOL      : return str ~ "bool";
        case TypeEnum.STRING    : return str ~ "string";
        case TypeEnum.SET       : return str ~ set.format();
        case TypeEnum.HASH      : return str ~ hash.format();
        case TypeEnum.ARRAY     : return str ~ array.format();
        case TypeEnum.AGGREGATE : return str ~ aggregate.format();
        case TypeEnum.TUPLE     : return str ~ tuple.format();
        case TypeEnum.FUNCPTR   : return str ~ funcPtr.format();
        case TypeEnum.STRUCT    : return str ~ structDef.format();
        case TypeEnum.VARIANT   : return str ~ variantDef.format();
        case TypeEnum.CHAN      : return str ~ chan.format();
        }
    }

    string formatFull() const
    {
        string str = "";
        if (constType)
        {
            str ~= "const ";
        }
        final switch (tag)
        {
        case TypeEnum.VOID:
        case TypeEnum.LONG:
        case TypeEnum.INT:
        case TypeEnum.SHORT:
        case TypeEnum.BYTE:
        case TypeEnum.FLOAT:
        case TypeEnum.DOUBLE:
        case TypeEnum.CHAR:
        case TypeEnum.BOOL:
        case TypeEnum.STRING:
        case TypeEnum.SET:
        case TypeEnum.HASH:
        case TypeEnum.ARRAY:
        case TypeEnum.AGGREGATE:
        case TypeEnum.TUPLE:
        case TypeEnum.FUNCPTR:
        case TypeEnum.CHAN:
            return this.format();
        case TypeEnum.STRUCT:
            return str ~ this.structDef.formatFull();
        case TypeEnum.VARIANT:
            return str ~ this.variantDef.formatFull();
        }
    }

    string formatMangle() const
    {
        string str = "";
        final switch (tag)
        {
        case TypeEnum.VOID:
        case TypeEnum.LONG:
        case TypeEnum.INT:
        case TypeEnum.SHORT:
        case TypeEnum.BYTE:
        case TypeEnum.FLOAT:
        case TypeEnum.DOUBLE:
        case TypeEnum.CHAR:
        case TypeEnum.BOOL:
        case TypeEnum.STRING:
            return "@B" ~ format();
        case TypeEnum.SET:
            return set.formatMangle();
        case TypeEnum.HASH:
            return hash.formatMangle();
        case TypeEnum.ARRAY:
            return array.formatMangle();
        case TypeEnum.AGGREGATE:
            return aggregate.formatMangle();
        case TypeEnum.TUPLE:
            return tuple.formatMangle();
        case TypeEnum.FUNCPTR:
            return funcPtr.formatMangle();
        case TypeEnum.CHAN:
            return chan.formatMangle();
        case TypeEnum.STRUCT:
            return structDef.formatMangle();
        case TypeEnum.VARIANT:
            return variantDef.formatMangle();
        }
    }

    auto size()
    {
        final switch (tag)
        {
        case TypeEnum.VOID      : return 0;
        case TypeEnum.LONG      : return 8;
        case TypeEnum.INT       : return 4;
        case TypeEnum.SHORT     : return 2;
        case TypeEnum.BYTE      : return 1;
        case TypeEnum.FLOAT     : return 4;
        case TypeEnum.DOUBLE    : return 8;
        case TypeEnum.CHAR      : return 1;
        case TypeEnum.BOOL      : return 1;
        case TypeEnum.STRING    : return PTR_SIZE;
        case TypeEnum.SET       : return PTR_SIZE;
        case TypeEnum.HASH      : return PTR_SIZE;
        case TypeEnum.ARRAY     : return PTR_SIZE;
        case TypeEnum.FUNCPTR   : return FAT_PTR_SIZE;
        case TypeEnum.STRUCT    : return PTR_SIZE;
        case TypeEnum.VARIANT   : return PTR_SIZE;
        case TypeEnum.CHAN      : return PTR_SIZE;
        // Tuples are allocated on the stack, to make tuple-return cheap
        case TypeEnum.TUPLE     : return tuple.types
                                              .map!(a => a.size)
                                              .array
                                              .getAlignedSize;
        // Any remaining aggregate placeholders in a type, after the
        // typechecker approved the code (which should be the only time
        // we care about the size of the types), must be placeholders for
        // struct or variant pointers, meaning any remaining aggregate
        // placeholder must be of size PTR_SIZE
        case TypeEnum.AGGREGATE : return PTR_SIZE;
        }
    }
}

// This function assumes that there is only a single definition of variants and
// structs, and that therefore if they have the same name and the same template
// instantiation parameters, if any, then they must be identical
bool cmp(Type* me, Type* o)
{
    if (me.constType != o.constType || me.tag != o.tag)
    {
        return false;
    }
    final switch (me.tag)
    {
    case TypeEnum.VOID:
    case TypeEnum.LONG:
    case TypeEnum.INT:
    case TypeEnum.SHORT:
    case TypeEnum.BYTE:
    case TypeEnum.FLOAT:
    case TypeEnum.DOUBLE:
    case TypeEnum.CHAR:
    case TypeEnum.BOOL:
    case TypeEnum.STRING:
        return true;
    case TypeEnum.SET:
        return me.set.setType.cmp(o.set.setType);
    case TypeEnum.HASH:
        return me.hash.keyType.cmp(o.hash.keyType)
            && me.hash.valueType.cmp(o.hash.valueType);
    case TypeEnum.ARRAY:
        return me.array.arrayType.cmp(o.array.arrayType);
    case TypeEnum.TUPLE:
        return me.tuple.types.length == o.tuple.types.length
            && zip(me.tuple.types, o.tuple.types)
              .map!(a => a[0].cmp(a[1]))
              .reduce!((a, b) => true == a && a == b);
    case TypeEnum.FUNCPTR:
        return me.funcPtr.returnType.cmp(o.funcPtr.returnType)
            && me.funcPtr.funcArgs.length == o.funcPtr.funcArgs.length
            && zip(me.funcPtr.funcArgs,
                   o.funcPtr.funcArgs)
              .map!(a => a[0].cmp(a[1]))
              .reduce!((a, b) => true == a && a == b);
    case TypeEnum.STRUCT:
        return me.structDef.name == o.structDef.name
            && (  me.structDef.templateParams.length
                == o.structDef.templateParams.length
                && (me.structDef.templateParams.length == 0
                 || (me.structDef.instantiated == o.structDef.instantiated
                     && zip(me.structDef.templateParams
                                         .map!(a => me.structDef.mappings[a]),
                             o.structDef.templateParams
                                         .map!(a =>  o.structDef.mappings[a]))
                       .map!(a => a[0].softcmp(a[1]))
                       .reduce!((a, b) => true == a && a == b))));
    case TypeEnum.VARIANT:
        return me.variantDef.name == o.variantDef.name
            && (  me.variantDef.templateParams.length
                == o.variantDef.templateParams.length
                && (me.variantDef.templateParams.length == 0
                 || (me.variantDef.instantiated == o.variantDef.instantiated
                     && zip(me.variantDef.templateParams
                                         .map!(a => me.variantDef.mappings[a]),
                             o.variantDef.templateParams
                                         .map!(a =>  o.variantDef.mappings[a]))
                       .map!(a => a[0].softcmp(a[1]))
                       .reduce!((a, b) => true == a && a == b))));
    case TypeEnum.AGGREGATE:
        return me.aggregate.typeName == o.aggregate.typeName
            && me.aggregate.templateInstantiations.length ==
             o.aggregate.templateInstantiations.length
            && reduce!((a, b) => true == a && a == b)(
                    true,
                    zip(me.aggregate.templateInstantiations,
                      o.aggregate.templateInstantiations)
                    .map!(a => a[0].softcmp(a[1])));
    case TypeEnum.CHAN:
        return me.chan.chanType.cmp(o.chan.chanType);
    }
}

bool softcmp(Type* me, Type* o)
{
    if (me.tag == o.tag)
    {
        if (me.isBasic && o.isBasic)
        {
            return true;
        }
        return me.cmp(o);
    }
    if (me.tag != o.tag)
    {
        if (me.tag != TypeEnum.AGGREGATE && o.tag != TypeEnum.AGGREGATE)
        {
            return false;
        }
        if (me.tag == TypeEnum.AGGREGATE && o.tag == TypeEnum.AGGREGATE)
        {
            return me.cmp(o);
        }
        if (o.tag == TypeEnum.AGGREGATE)
        {
            swap(me, o);
        }
        if (o.tag == TypeEnum.VARIANT)
        {
            return me.aggregate.typeName == o.variantDef.name
                && me.aggregate.templateInstantiations.length ==
                    o.variantDef.templateParams.length
                && reduce!((a, b) => true == a && a == b)(
                        true,
                        zip(me.aggregate.templateInstantiations,
                             o.variantDef
                              .templateParams
                              .map!(a => o.variantDef.mappings[a])
                              .array)
                        .map!(a => a[0].softcmp(a[1])));
        }
        if (o.tag == TypeEnum.STRUCT)
        {
            return me.aggregate.typeName == o.structDef.name
                && me.aggregate.templateInstantiations.length ==
                    o.structDef.templateParams.length
                && reduce!((a, b) => true == a && a == b)(
                        true,
                        zip(me.aggregate.templateInstantiations,
                             o.structDef
                              .templateParams
                              .map!(a => o.structDef.mappings[a])
                              .array)
                        .map!(a => a[0].softcmp(a[1])));
        }
    }
    return false;
}

// Given whatever the current allocated size is, and given the size of the
// next thing to allocate for, determine how much padding is necessary for the
// next size
auto getPadding(int curSize, int nextSize)
{
    auto mod = 0;
    if ((mod = curSize % nextSize) != 0)
    {
        return nextSize - mod;
    }
    return 0;
}

// The byte number returned is the first byte of the data being indexed to.
// Note that if index >= entries.length, the value returned is the total
// aligned size
auto getAlignedIndexOffset(int[] entries, ulong index)
{
    auto size = 0;
    if (entries.length == 0 || index == 0)
    {
        return 0;
    }
    size += entries[0];
    foreach (i, e; entries[1..$])
    {
        if (index == i + 1)
        {
            return size + getPadding(size, e);
        }
        size += getPadding(size, e) + e;
    }
    return size;
}

auto getAlignedSize(int[] entries)
{
    return getAlignedIndexOffset(entries, entries.length);
}

// Return a value that is the next highest multiple of 8 of the input, or the
// input if it's already a multiple of 8
uint stackAlignSize(uint size)
{
    if (size % 8 == 0)
    {
        return size;
    }
    else if (size < 8)
    {
        return 8;
    }
    else if (size > 8)
    {
        return size + (8 - (size % 8));
    }
    assert(false, "Unrechable");
}

struct VarTypePair
{
    string varName;
    Type* type;
    bool closedOver;

    auto format()
    {
        return varName ~ ": " ~ type.format();
    }

    auto formatFull()
    {
        return varName ~ ": " ~ type.formatFull();
    }
}

// The 'header' for a function type. Note that a function can be any of the
// three of being a closure, a struct member function, or neither. A function
// cannot both be a closure and a struct member function, so there will only
// ever be, at most, a single 'implicit' leading argument, whether it be
// an environment-pointer or a 'this' pointer
struct FuncSig
{
    // The actual name of the function; that which can be called
    string funcName;
    // Template args
    string[] templateParams;
    // Types used to instantiate template
    Type*[] templateTypes;
    // A possibly zero-length list of variables that are closed over, indicating
    // this is a closure function. If the length is zero, the number of
    // arguments to the actual implementation of the function is the number
    // of arguments in 'funcArgs', otherwise there is an additional
    // environment-pointer argument
    VarTypePair*[] closureVars;
    // A possibly-empty string indicating the struct that this function is a
    // member of. If this string is empty, then the number of arguments to the
    // actual implementation of this function is the number of arguments in
    // 'funcArgs', otherwise there is an additional 'this' pointer
    string memberOf;
    // The types of the arguments to the function, in the order they appeared
    // in the original argument list
    VarTypePair*[] funcArgs;
    // The return type. Since it's a bare type, it can possibly be a tuple of
    // types
    Type* returnType;
    // For expanding templates
    FuncDefNode funcDefNode;
    // The total number of bytes named variables will use on the stack
    uint stackVarAllocSize;
    // Whether the "function" is actually a unittest block
    bool isUnittest;

    auto format()
    {
        string str = "";
        str ~= "func " ~ funcName;
        if (templateParams.length > 0)
        {
            str ~= "(" ~ templateParams.join(", ") ~ ")";
        }
        str ~= "(" ~ funcArgs.map!(a => a.format).join(", ") ~ ")";
        if (returnType !is null)
        {
            str ~= ": " ~ returnType.format;
        }
        return str;
    }
}

bool isBasic(Type* type)
{
    switch (type.tag)
    {
    case TypeEnum.VOID:
    case TypeEnum.LONG:
    case TypeEnum.INT:
    case TypeEnum.SHORT:
    case TypeEnum.BYTE:
    case TypeEnum.FLOAT:
    case TypeEnum.DOUBLE:
    case TypeEnum.CHAR:
    case TypeEnum.BOOL:
    case TypeEnum.STRING:
        return true;
    default:
        return false;
    }
}

bool isIntegral(Type* type)
{
    switch (type.tag)
    {
    case TypeEnum.LONG:
    case TypeEnum.INT:
    case TypeEnum.SHORT:
    case TypeEnum.BYTE:
        return true;
    default:
        return false;
    }
}

bool isFloat(Type* type)
{
    switch (type.tag)
    {
    case TypeEnum.FLOAT:
    case TypeEnum.DOUBLE:
        return true;
    default:
        return false;
    }
}

bool isNumeric(Type* type)
{
    switch (type.tag)
    {
    case TypeEnum.LONG:
    case TypeEnum.INT:
    case TypeEnum.SHORT:
    case TypeEnum.BYTE:
    case TypeEnum.FLOAT:
    case TypeEnum.DOUBLE:
        return true;
    default:
        return false;
    }
}

bool isRefType(Type* type)
{
    switch (type.tag)
    {
    case TypeEnum.ARRAY:
    case TypeEnum.STRING:
    case TypeEnum.HASH:
    case TypeEnum.SET:
    case TypeEnum.FUNCPTR:
    case TypeEnum.STRUCT:
    case TypeEnum.VARIANT:
    case TypeEnum.CHAN:
        return true;
    default:
        return false;
    }
}

bool needsSignExtend(Type* type)
{
    switch (type.tag)
    {
    case TypeEnum.INT:
    case TypeEnum.SHORT:
    case TypeEnum.BYTE:
        return true;
    default:
        return false;
    }
}

// Return as a result the larger of the two numeric types
Type* promoteNumeric(Type* left, Type* right, ASTNode node)
{
    if (!left.isNumeric || !right.isNumeric)
    {
        throw new Exception(
            errorHeader(node) ~ "\n"
            ~ "Cannot promote non-numeric type.\n"
            ~ "Left Type : " ~ left.format ~ "\n"
            ~ "Right Type: " ~ right.format
        );
    }
    auto promote = new Type;
    switch (left.tag)
    {
    case TypeEnum.BYTE     : promote.tag = right.tag; return promote;
    case TypeEnum.SHORT    :
        switch (right.tag)
        {
        case TypeEnum.BYTE : promote.tag = left.tag;  return promote;
        default            : promote.tag = right.tag; return promote;
        }
    case TypeEnum.INT      :
        switch (right.tag)
        {
        case TypeEnum.BYTE : promote.tag = left.tag;  return promote;
        case TypeEnum.SHORT: promote.tag = left.tag;  return promote;
        default            : promote.tag = right.tag; return promote;
        }
    case TypeEnum.LONG     :
        switch (right.tag)
        {
        case TypeEnum.BYTE : promote.tag = left.tag;  return promote;
        case TypeEnum.SHORT: promote.tag = left.tag;  return promote;
        case TypeEnum.INT  : promote.tag = left.tag;  return promote;
        default            : promote.tag = right.tag; return promote;
        }
    case TypeEnum.FLOAT    :
        switch (right.tag)
        {
        case TypeEnum.BYTE : promote.tag = left.tag;  return promote;
        case TypeEnum.SHORT: promote.tag = left.tag;  return promote;
        case TypeEnum.INT  : promote.tag = left.tag;  return promote;
        case TypeEnum.LONG : promote.tag = left.tag;  return promote;
        default            : promote.tag = right.tag; return promote;
        }
    case TypeEnum.DOUBLE   : promote.tag = left.tag;  return promote;
    default:
        assert(false, "Unreachable in promoteNumeric.");
    }
}

mixin template TypeVisitors()
{
    string[] templateParams;
    Type*[][] builderStack;

    void visit(TypeIdNode node)
    {
        node.children[0].accept(this);
    }

    void visit(BasicTypeNode node)
    {
        auto basicType = (cast(ASTTerminal)node.children[0]).token;
        auto builder = new Type();
        final switch (basicType)
        {
        case "long"  : builder.tag = TypeEnum.LONG;   break;
        case "int"   : builder.tag = TypeEnum.INT;    break;
        case "short" : builder.tag = TypeEnum.SHORT;  break;
        case "byte"  : builder.tag = TypeEnum.BYTE;   break;
        case "float" : builder.tag = TypeEnum.FLOAT;  break;
        case "double": builder.tag = TypeEnum.DOUBLE; break;
        case "char"  : builder.tag = TypeEnum.CHAR;   break;
        case "bool"  : builder.tag = TypeEnum.BOOL;   break;
        case "string": builder.tag = TypeEnum.STRING; break;
        }
        builderStack[$-1] ~= builder;
    }

    void visit(ArrayTypeNode node)
    {
        auto array = new ArrayType();
        if (node.children.length > 1)
        {
            node.children[0].accept(this);
            auto allocType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!isIntegral(allocType))
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Can only use integral value to prealloc"
                );
            }
            node.children[1].accept(this);
        }
        else
        {
            node.children[0].accept(this);
        }
        array.arrayType = builderStack[$-1][$-1];
        if (node.children.length > 1 && (array.arrayType.tag == TypeEnum.STRUCT
            || array.arrayType.tag == TypeEnum.VARIANT))
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Cannot preallocate space for arrays of structs or variants"
            );
        }
        auto type = new Type();
        type.tag = TypeEnum.ARRAY;
        type.array = array;
        builderStack[$-1] = builderStack[$-1][0..$-1] ~ type;
    }

    void visit(SetTypeNode node)
    {
        node.children[0].accept(this);
        auto set = new SetType();
        set.setType = builderStack[$-1][$-1];
        auto type = new Type();
        type.tag = TypeEnum.SET;
        type.set = set;
        builderStack[$-1] = builderStack[$-1][0..$-1] ~ type;
    }

    void visit(HashTypeNode node)
    {
        node.children[0].accept(this);
        node.children[1].accept(this);
        auto hash = new HashType();
        hash.keyType = builderStack[$-1][$-2];
        hash.valueType = builderStack[$-1][$-1];
        auto type = new Type();
        type.tag = TypeEnum.HASH;
        type.hash = hash;
        builderStack[$-1] = builderStack[$-1][0..$-2] ~ type;
    }

    void visit(TypeTupleNode node)
    {
        auto tuple = new TupleType();
        foreach (child; node.children)
        {
            child.accept(this);
            tuple.types ~= builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
        }
        auto type = new Type();
        type.tag = TypeEnum.TUPLE;
        type.tuple = tuple;
        builderStack[$-1] ~= type;
    }

    void visit(ChanTypeNode node)
    {
        auto chan = new ChanType();
        node.children[0].accept(this);
        auto chanType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        chan.chanType = chanType.copy;
        auto wrap = new Type();
        wrap.chan = chan;
        wrap.tag = TypeEnum.CHAN;
        builderStack[$-1] ~= wrap;
    }

    void visit(FuncRefTypeNode node)
    {
        auto funcRefType = new FuncPtrType();
        Type*[] funcArgs;
        foreach (child; node.children[0..$-1])
        {
            child.accept(this);
            funcArgs ~= builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
        }
        funcRefType.funcArgs = funcArgs;
        auto retTypeNode = cast(FuncRefRetTypeNode)node.children[$-1];
        if (retTypeNode.children.length == 0)
        {
            auto voidRetType = new Type();
            voidRetType.tag = TypeEnum.VOID;
            funcRefType.returnType = voidRetType;
        }
        else
        {
            retTypeNode.children[0].accept(this);
            funcRefType.returnType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
        }
        auto wrap = new Type();
        wrap.tag = TypeEnum.FUNCPTR;
        wrap.funcPtr = funcRefType;
        builderStack[$-1] ~= wrap;
    }

    void visit(FuncRefRetTypeNode node) {}

    void visit(TemplateTypeParamsNode node)
    {
        if (node.children.length > 0)
        {
            // Visit TemplateTypeParamListNode
            node.children[0].accept(this);
        }
    }

    void visit(TemplateTypeParamListNode node)
    {
        templateParams = [];
        foreach (child; node.children)
        {
            child.accept(this);
            templateParams ~= id;
        }
    }

    void visit(TemplateInstantiationNode node)
    {
        node.children[0].accept(this);
    }

    void visit(TemplateParamNode node)
    {
        node.children[0].accept(this);
    }

    void visit(TemplateParamListNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(TemplateAliasNode node)
    {
        node.children[0].accept(this);
    }
}
