import std.stdio;
import std.algorithm;
import std.range;
import parser;

const PTR_SIZE = 8;

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

    string format()
    {
        return "[]" ~ arrayType.format();
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

    string format()
    {
        return "[" ~ keyType.format() ~ "]" ~ valueType.format();
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

    string format()
    {
        return "<>" ~ setType.format();
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

    string format()
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

    string format()
    {
        return "(" ~ types.map!(a => a.format()).join(", ") ~ ")";
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
    string format()
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

    string format()
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
    private bool instantiated;
    private Type*[string] mappings;

    StructType* copy()
    {
        auto c = new StructType();
        c.name = this.name;
        c.templateParams = this.templateParams;
        c.members = this.members
                        .map!(a => a.copy)
                        .array;
        return c;
    }

    string formatFull()
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
                str ~= templateParams.map!(a => mappings[a].format).join(", ");
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

    string format()
    {
        string str = "";
        str ~= name;
        if (templateParams.length > 0)
        {
            if (instantiated)
            {
                str ~= "!(";
                str ~= templateParams.map!(a => mappings[a].format).join(", ");
                str ~= ")";
            }
            else
            {
                str ~= "(" ~ templateParams.join(", ") ~ ")";
            }
        }
        return str;
    }

    // Attempt to replace the template name placeholders with actual types
    // using a passed name: string -> concrete-type: Type* map
    void instantiate(Type*[string] mappings)
    {
        mixin descend;

        auto missing = mappings.keys.setSymmetricDifference(templateParams);
        if (missing.walkLength > 0)
        {
            "StructType.instantiate(): The passed mapping does not contain\n"
            "  keys that correspond exactly with the known template parameter\n"
            "  names. Not attempting to instantiate.\n"
            "  The missing mappings are: ".writeln;
            foreach (name; missing)
            {
                writeln("  ", name);
            }
        }
        foreach (ref member; members)
        {
            descend(member.type);
        }
        instantiated = true;
        this.mappings = mappings;
    }

    // The size of the struct on the heap is the total aligned size of all the
    // members
    auto size()
    {
        return members.map!(a => a.size)
                      .array
                      .getAlignedSize;
    }
}

struct VariantMember
{
    string constructorName;
    // Intended to be a tuple
    Type* constructorElems;

    VariantMember copy()
    {
        auto c = VariantMember();
        c.constructorName = this.constructorName;
        c.constructorElems = this.constructorElems.copy;
        return c;
    }

    string format()
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
    private bool instantiated;
    private Type*[string] mappings;

    VariantType* copy()
    {
        auto c = new VariantType();
        c.name = this.name;
        c.templateParams = this.templateParams;
        c.members = this.members
                        .map!(a => a.copy)
                        .array;
        return c;
    }

    string formatFull()
    {
        string str = "";
        str ~= "variant " ~ name;
        if (templateParams.length > 0)
        {
            str ~= "(" ~ templateParams.join(", ") ~ ")";
        }
        str ~= " {\n";
        foreach (member; members)
        {
            str ~= "    " ~ member.format() ~ "\n";
        }
        str ~= "}";
        return str;
    }

    string format()
    {
        string str = "";
        str ~= name;
        if (templateParams.length > 0)
        {
            if (instantiated)
            {
                str ~= "!(";
                str ~= templateParams.map!(a => mappings[a].format).join(", ");
                str ~= ")";
            }
            else
            {
                str ~= "(" ~ templateParams.join(", ") ~ ")";
            }
        }
        return str;
    }

    // Attempt to replace the template name placeholders with actual types
    // using a passed name: string -> concrete-type: Type* map
    void instantiate(Type*[string] mappings)
    {
        mixin descend;

        auto missing = mappings.keys.setSymmetricDifference(templateParams);
        if (missing.walkLength > 0)
        {
            "VariantType.instantiate(): The passed mapping does not contain\n"
            "  keys that correspond exactly with the known template parameter\n"
            "  names. Not attempting to instantiate.\n"
            "  The missing mappings are: ".writeln;
            foreach (name; missing)
            {
                writeln("  ", name);
            }
        }
        foreach (ref member; members)
        {
            descend(member.constructorElems);
        }
        instantiated = true;
        templateParams = [];
        this.mappings = mappings;
    }

    // The total size of a variant value on the heap is the size of the largest
    // constructor
    auto size()
    {
        return members.map!(a => a.size)
                      .reduce!(max);
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
        }
        return c;
    }

    string format()
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
        }
    }

    bool cmp(const Type* o) const
    {
        if (constType != o.constType || tag != o.tag)
        {
            return false;
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
            return true;
        case TypeEnum.SET:
            return set.setType.cmp(o.set.setType);
        case TypeEnum.HASH:
            return hash.keyType.cmp(o.hash.keyType)
                && hash.valueType.cmp(o.hash.valueType);
        case TypeEnum.ARRAY:
            return array.arrayType.cmp(o.array.arrayType);
        case TypeEnum.TUPLE:
            return tuple.types.length == o.tuple.types.length
                && zip(tuple.types, o.tuple.types)
                  .map!(a => a[0].cmp(a[1]))
                  .reduce!((a, b) => true == a && a == b);
        case TypeEnum.FUNCPTR:
            return funcPtr.returnType.cmp(o.funcPtr.returnType)
                && funcPtr.funcArgs.length == o.funcPtr.funcArgs.length
                && zip(funcPtr.funcArgs,
                       o.funcPtr.funcArgs)
                  .map!(a => a[0].cmp(a[1]))
                  .reduce!((a, b) => true == a && a == b);
        case TypeEnum.STRUCT:
            return structDef.name == o.structDef.name
                && structDef.members.length == o.structDef.members.length
                && zip(structDef.members,
                       o.structDef.members)
                  .map!(a => a[0].type.cmp(a[1].type))
                  .reduce!((a, b) => true == a && a == b);
        case TypeEnum.VARIANT:
            return variantDef.name == o.variantDef.name
                && zip(variantDef.members,
                       o.variantDef.members)
                  .map!(a => a[0].constructorName == a[1].constructorName
                          && a[0].constructorElems.cmp(a[1].constructorElems))
                  .reduce!((a, b) => true == a && a == b);
        case TypeEnum.AGGREGATE:
            return aggregate.typeName == o.aggregate.typeName
                && aggregate.templateInstantiations.length ==
                 o.aggregate.templateInstantiations.length
                && reduce!((a, b) => true == a && a == b)(
                        true,
                        zip(aggregate.templateInstantiations,
                          o.aggregate.templateInstantiations)
                        .map!(a => a[0].cmp(a[1])));
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
        case TypeEnum.FUNCPTR   : return PTR_SIZE;
        case TypeEnum.STRUCT    : return PTR_SIZE;
        case TypeEnum.VARIANT   : return PTR_SIZE;
        // Tuples are allocated on the stack, to make tuple-return cheap
        case TypeEnum.TUPLE     : return tuple.types
                                              .map!(a => a.size)
                                              .array
                                              .getAlignedSize;
        // Aggregate types are simply placeholders for instantiated struct and
        // variant types. If we are comparing against an aggregate, we failed
        // to perform an instantiation somewhere
        case TypeEnum.AGGREGATE :
            throw new Exception("Aggregate type was not instantiated");
        }
    }
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

struct VarTypePair
{
    string varName;
    Type* type;
    bool closedOver;

    auto format()
    {
        return varName ~ ": " ~ type.format();
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
    // Body blocks node, for expanding templates
    FuncBodyBlocksNode funcBodyBlocks;

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

// Return as a result the larger of the two numeric types
Type* promoteNumeric(Type* left, Type* right)
{
    if (!left.isNumeric || !right.isNumeric)
    {
        throw new Exception("Cannot promote non-numeric type.");
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

// This is mixed into the StructType and VariantType instantiate() definitions,
// as the code is exactly the same for both, but they each need closure access
// to the "mappings" argument of the instantiate() function, and passing
// the "mappings" as an argument to this function is silly since it would never
// change on each recursion, and there doesn't seem to be a way to pass the
// argument as a const variable without having to cast the constness off when
// trying to assign pointer values in the mappings back to the member types,
// which is gross
mixin template descend()
{
    // Recursively descend the type, looking for aggregate entries that
    // are in the mapping. An aggregate type is defined simply as a string
    // referring to its actual type, which means it is either referring to
    // a struct or variant definition, or is a template placeholder.
    // Even though the parent is null, the case of the top level type
    // being an aggregate is handled correctly
    void descend(ref Type* typeMember, Type* typeParent = null)
    {
        // Used to know which of the two sides of a hash type we're dealing
        // with after a descension
        static index = 0;
        switch (typeMember.tag)
        {
        // If the type is an aggregate, it is either a template placeholder
        // or not. If it is, and this is the top level call of descend, then
        // simply update the type member with its new type. If we're in
        // a recursion of descend, then update the parent's pointer to this
        // type with the new type
        case TypeEnum.AGGREGATE:
            if (typeMember.aggregate.typeName in mappings)
            {
                if (typeParent is null)
                {
                    typeMember = mappings[typeMember.aggregate.typeName];
                }
                else
                {
                    switch(typeParent.tag)
                    {
                    case TypeEnum.SET:
                        typeParent.set.setType =
                            mappings[typeMember.aggregate.typeName];
                        break;
                    case TypeEnum.HASH:
                        switch (index)
                        {
                        case 0:
                            typeParent.hash.keyType =
                                mappings[typeMember.aggregate.typeName];
                            break;
                        default:
                            typeParent.hash.valueType =
                                mappings[typeMember.aggregate.typeName];
                            break;
                        }
                        break;
                    case TypeEnum.ARRAY:
                        typeParent.array.arrayType =
                            mappings[typeMember.aggregate.typeName];
                        break;
                    default:
                        break;
                    }
                }
            }
            else
            {
                foreach (ref inner; typeMember.aggregate.templateInstantiations)
                {
                    descend(inner);
                }
            }
            break;
        case TypeEnum.SET:
            descend(typeMember.set.setType, typeMember);
            break;
        case TypeEnum.HASH:
            index = 0;
            descend(typeMember.hash.keyType, typeMember);
            index = 1;
            descend(typeMember.hash.valueType, typeMember);
            break;
        case TypeEnum.ARRAY:
            descend(typeMember.array.arrayType, typeMember);
            break;
        default:
            break;
        }
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
        node.children[0].accept(this);
        auto array = new ArrayType();
        array.arrayType = builderStack[$-1][$-1];
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
