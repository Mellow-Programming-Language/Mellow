import std.stdio;
import std.string;
import std.conv;
import std.algorithm;
import std.array;

immutable uint PTR_SIZE = 4;

enum StorageClass
{
    CONST,
    REF
}

enum TypeID
{
    PRIMITIVE,
    STRUCT,
    VARIANT,
    TUPLE,
    INDIRECTION
}

interface Type
{
    // The minimum size required to store the type. The sum total number of
    // bytes of each sub component, ignoring alignment
    uint getPackedSize() const;
    // The size of the type, if each component of the type were aligned
    // according to the C alignment rules.
    uint getAlignedSize() const;
    // Get the size of the largest primitive type in a complex type composition
    uint getLargestPrimSize() const;
    // Return the typeID of the type. Use this for casting
    TypeID getTypeID() const;
    // Return stringification of type name
    string getTypename() const;
}

string createPrimitiveType(string name, uint size)
{
    string def = ""
        ~ `class Prim_` ~ name.capitalize() ~ ` : Type {`         ~ "\n"
        ~ `    string getTypename() const`                             ~ "\n"
        ~ `    { return "` ~ name ~ `"; }`                             ~ "\n"
        ~ `    uint getAlignedSize() const`                            ~ "\n"
        ~ `    { return ` ~ size.to!string ~ `; }`                     ~ "\n"
        ~ `    uint getPackedSize() const`                             ~ "\n"
        ~ `    { return ` ~ size.to!string ~ `; }`                     ~ "\n"
        ~ `    uint getLargestPrimSize() const`                        ~ "\n"
        ~ `    { return ` ~ size.to!string ~ `; }`                     ~ "\n"
        ~ `    TypeID getTypeID() const`                               ~ "\n"
        ~ `    { return TypeID.PRIMITIVE; }`                           ~ "\n"
        ~ `}`                                                          ~ "\n";
    return def;
}

mixin(createPrimitiveType("double", 8));
mixin(createPrimitiveType("float",  4));
mixin(createPrimitiveType("long",   8));
mixin(createPrimitiveType("ulong",  8));
mixin(createPrimitiveType("int",    4));
mixin(createPrimitiveType("uint",   4));
mixin(createPrimitiveType("short",  2));
mixin(createPrimitiveType("ushort", 2));
mixin(createPrimitiveType("byte",   1));
mixin(createPrimitiveType("ubyte",  1));
mixin(createPrimitiveType("char",   1));
mixin(createPrimitiveType("bool",   1));
// Space for the length of the string plus a pointer to the array of chars
mixin(createPrimitiveType("string", 4 + PTR_SIZE));

enum IndTag
{
    PTR,
    DYN_ARR,
    HASH
}

// Ind[irection]
interface Ind
{
    IndTag getInd() const;
    string indString() const;
}

class PtrInd : Ind
{
    IndTag getInd() const
    {
        return IndTag.PTR;
    }

    string indString() const
    {
        return "*";
    }
}

class DynArrInd : Ind
{
    IndTag getInd() const
    {
        return IndTag.DYN_ARR;
    }

    string indString() const
    {
        return "[]";
    }
}

class HashInd : Ind
{
    Type indexType;

    IndTag getInd() const
    {
        return IndTag.HASH;
    }

    string indString() const
    {
        return "[" ~ indexType.getTypename ~ "]";
    }

    auto getIndexType() const
    {
        return indexType;
    }
}

// Ind[irection] type
class IndType : Type
{
    // This kind of indirection
    const Ind ind;
    // The type this level of indirection is pointing to or working with.
    // So if this type is representing *[][]int, then ind would be PtrInd,
    // and 'type' would be an IndirectionType representing [][]int
    const Type type;

    this (Ind ind, Type type)
    {
        this.ind = ind;
        this.type = type;
    }

    uint getAlignedSize() const
    {
        return PTR_SIZE;
    }

    uint getPackedSize() const
    {
        return PTR_SIZE;
    }

    uint getLargestPrimSize() const
    {
        return PTR_SIZE;
    }

    string getTypename() const
    {
        return ind.indString() ~ type.getTypename();
    }

    TypeID getTypeID() const
    {
        return TypeID.INDIRECTION;
    }

    auto getPointedType() const
    {
        return type;
    }
}

unittest
{
    VarTypePair[] pairs;
    pairs ~= new VarTypePair("Prim_Long", new Prim_Long());
    pairs ~= new VarTypePair("Prim_Int", new Prim_Int());
    pairs ~= new VarTypePair("Prim_Short", new Prim_Short());
    pairs ~= new VarTypePair("Prim_Byte", new Prim_Byte());
    auto str = new Struct("myStruct", pairs);
    auto ind = new IndType(new PtrInd(), str);
    assert(ind.getAlignedSize() == PTR_SIZE);
    assert(ind.getPackedSize() == PTR_SIZE);
    assert(ind.getTypename() == "*myStruct");
}

class VarTypePair
{
    const string varName;
    const Type type;
    const bool isConst;
    const bool isStatic;

    this (string varName, Type type,
        bool isConst = false, bool isStatic = false)
    {
        this.varName = varName;
        this.type = type;
        this.isConst = isConst;
        this.isStatic = isStatic;
    }

    string getVarName() const
    {
        return varName;
    }

    auto getType()
    {
        return type;
    }
}

auto access(alias accessor, Q)(Q aggregate, uint index) const
{
    return accessor(aggregate, index);
}

template memoryAlgs(alias aggIndex, alias aggregate)
{
    private auto calcPadding(const uint curTotal, const uint alignSize)
    {
        // If we haven't started laying out memory yet, then we need no padding
        if (curTotal == 0)
        {
            return 0;
        }
        uint padding;
        if (curTotal >= alignSize)
        {
            auto modAlign = curTotal % alignSize;
            if (modAlign > 0)
            {
                padding = alignSize - modAlign;
            }
        }
        else
        {
            padding = alignSize - curTotal;
        }
        return padding;
    }

    // The offset from 0 that the sub component at 'index' would start in bytes
    // assuming alignment rules. The first component will always be 0, and the
    // second component would be (sizeof(component(0)) + padding)
    auto getOffsetOfSubpart(uint index)
    {
        if (index == 0)
        {
            return 0;
        }
        uint totalBytes = 0;
        for (uint i = 0; i < index; i++)
        {
            uint curAlignSize;
            uint curTotalSize;
            curAlignSize = aggregate.access!(aggIndex)(i)
                                    .getLargestPrimSize();
            // Get the total size of the aligned type, which may be different
            // than its alignment requirements
            curTotalSize = aggregate.access!(aggIndex)(i)
                                    .getAlignedSize();
            // Add the difference between where the alignment needs to be and
            // where it is. Example: totalBytes is 5, and curAlignSize is 4,
            // then add padding of 3 to bring totalBytes to 8, such that
            // 8 % 4 == 0
            totalBytes += calcPadding(totalBytes, curAlignSize);
            // Add the total size of the type to the running total, which at
            // this point accounts for the padding required for the type as
            // well
            totalBytes += curTotalSize;
        }
        uint finalAlignSize;
        finalAlignSize = aggregate.access!(aggIndex)(index)
                                .getLargestPrimSize();
        totalBytes += calcPadding(totalBytes, finalAlignSize);
        return totalBytes;
    }

    auto getAlignedSize()
    {
        if (aggregate.length == 0)
        {
            return 0;
        }
        uint totalBytes = 0;
        uint maxAlign = 0;
        // Iterate over the types in the aggregate
        for (uint i = 0; i < aggregate.length; i++)
        {
            // For each type, we need both the alignment the type must receive,
            // and the total size of the type when it itself is aligned
            uint curAlignSize;
            uint curTotalSize;
            curAlignSize = aggregate.access!(aggIndex)(i)
                                    .getLargestPrimSize();
            // Get the total size of the aligned type, which may be different
            // than its alignment requirements
            curTotalSize = aggregate.access!(aggIndex)(i)
                                    .getAlignedSize();
            // Add the difference between where the alignment needs to be and
            // where it is. Example: totalBytes is 5, and curAlignSize is 4,
            // then add padding of 3 to bring totalBytes to 8, such that
            // 8 % 4 == 0
            totalBytes += calcPadding(totalBytes, curAlignSize);
            // Add the total size of the type to the running total, which at
            // this point accounts for the padding required for the type as
            // well
            totalBytes += curTotalSize;
            // Keep track of whatever the largest single element is, as we
            // need to pad the end to align with this size
            if (curAlignSize > maxAlign)
            {
                maxAlign = curAlignSize;
            }
        }
        // Align the aggregate to the size of the largest element
        uint maxAlignMod = totalBytes % maxAlign;
        if (maxAlignMod != 0)
        {
            totalBytes += maxAlign - maxAlignMod;
        }
        return totalBytes;
    }

    // The number of bytes that the largest primitive type takes up in a
    // composed type. Will descend into the type recursively, so if this is
    // called on a struct that contains structs that contain structs, it will
    // descend into the deepest parts of the type and find the biggest
    // primitive out of all of them
    auto getLargestPrimSize()
    {
        uint maxBytes = 0;
        for (uint i = 0; i < aggregate.length; i++)
        {
            maxBytes = max(maxBytes,
                           aggregate.access!(aggIndex)(i).getLargestPrimSize());
        }
        return maxBytes;
    }
}

class TupleType : Type
{
    const Type[] tuple;
    const TypeID id;

    this (const Type[] tuple)
    {
        this.tuple = tuple;
        this.id = TypeID.TUPLE;
    }

    this (VarTypePair[] typePairs)
    {
        const(Type)[] types;
        foreach (typePair; typePairs)
        {
            types ~= typePair.getType();
        }
        this(types);
    }

    uint getLargestPrimSize() const
    {
        return memoryAlgs!((a, b) => a[b], tuple).getLargestPrimSize();
    }

    uint getPackedSize() const
    {
        return reduce!((a, b) => a + b.getPackedSize())(0, tuple);
    }

    uint getAlignedSize() const
    {
        return memoryAlgs!((a, b) => a[b], tuple).getAlignedSize();
    }

    TypeID getTypeID() const
    {
        return TypeID.TUPLE;
    }

    uint getNumSubparts() const
    {
        return tuple.length.to!uint;
    }

    uint getOffsetOfSubpart(uint index) const
    in
    {
        assert(index < tuple.length);
    }
    body
    {
        return memoryAlgs!((a, b) => a[b], tuple).getOffsetOfSubpart(index);
    }

    Type getTypeOfSubpart(uint index) const
    in
    {
        assert(index < tuple.length);
    }
    body
    {
        return cast(Type)tuple[index];
    }

    string getTypename() const
    {
        string fullname = "";
        foreach (name; tuple.map!(a => a.getTypename()))
        {
            fullname ~= name ~ " ";
        }
        return fullname[0..$-1];
    }
}

unittest
{
    struct one
    {
        long w;
        int x;
        short y;
        byte z;
    }
    Type[] types;
    types ~= new Prim_Long();
    types ~= new Prim_Int();
    types ~= new Prim_Short();
    types ~= new Prim_Byte();
    auto tuple = new TupleType(types);
    assert(tuple.getPackedSize() == 15);
    assert(tuple.getAlignedSize() == one.sizeof);
    assert(tuple.getOffsetOfSubpart(0) == one.w.offsetof);
    assert(tuple.getOffsetOfSubpart(1) == one.x.offsetof);
    assert(tuple.getOffsetOfSubpart(2) == one.y.offsetof);
    assert(tuple.getOffsetOfSubpart(3) == one.z.offsetof);
    struct two
    {
        byte w;
        long x;
        short y;
        int z;
    }
    types = [];
    types ~= new Prim_Byte();
    types ~= new Prim_Long();
    types ~= new Prim_Short();
    types ~= new Prim_Int();
    tuple = new TupleType(types);
    assert(tuple.getPackedSize() == 15);
    assert(tuple.getAlignedSize() == 24);
    assert(tuple.getOffsetOfSubpart(0) == two.w.offsetof);
    assert(tuple.getOffsetOfSubpart(1) == two.x.offsetof);
    assert(tuple.getOffsetOfSubpart(2) == two.y.offsetof);
    assert(tuple.getOffsetOfSubpart(3) == two.z.offsetof);
    struct three
    {
        byte w;
        long x;
        byte ww;
        short y;
        byte www;
        int z;
    }
    types = [];
    types ~= new Prim_Byte();
    types ~= new Prim_Long();
    types ~= new Prim_Byte();
    types ~= new Prim_Short();
    types ~= new Prim_Byte();
    types ~= new Prim_Int();
    tuple = new TupleType(types);
    assert(tuple.getPackedSize() == 17);
    assert(tuple.getAlignedSize() == 32);
    assert(tuple.getOffsetOfSubpart(0) == three.w.offsetof);
    assert(tuple.getOffsetOfSubpart(1) == three.x.offsetof);
    assert(tuple.getOffsetOfSubpart(2) == three.ww.offsetof);
    assert(tuple.getOffsetOfSubpart(3) == three.y.offsetof);
    assert(tuple.getOffsetOfSubpart(4) == three.www.offsetof);
    assert(tuple.getOffsetOfSubpart(5) == three.z.offsetof);
}

class Struct : Type
{
    const string typename;
    const VarTypePair[] varTypePairs;
    const TypeID id;

    this (const string typename, const VarTypePair[] varTypePairs)
    {
        this.typename = typename;
        this.varTypePairs = varTypePairs;
        this.id = TypeID.STRUCT;
    }

    string getTypename() const
    {
        return typename;
    }

    uint getAlignedSize() const
    {
        return memoryAlgs!((a, b) => a[b].type, varTypePairs).getAlignedSize();
    }

    uint getPackedSize() const
    {
        return reduce!((a, b) => a + b.type.getPackedSize)(0, varTypePairs);
    }

    uint getLargestPrimSize() const
    {
        return memoryAlgs!((a, b) => a[b].type, varTypePairs)
            .getLargestPrimSize();
    }

    TypeID getTypeID() const
    {
        return TypeID.STRUCT;
    }

    uint getNumSubparts() const
    {
        return varTypePairs.length.to!uint;
    }

    uint getOffsetOfSubpart(uint index) const
    in
    {
        assert(index < varTypePairs.length);
    }
    body
    {
        return memoryAlgs!
            ((a, b) => a[b].type, varTypePairs)
            .getOffsetOfSubpart(index);
    }

    Type getTypeOfSubpart(uint index) const
    in
    {
        assert(index < varTypePairs.length);
    }
    body
    {
        return cast(Type)varTypePairs[index].type;
    }
}

unittest
{
    struct first
    {
        int x;
        long w;
        byte z;
        short y;
    }
    VarTypePair[] pairs;
    pairs ~= new VarTypePair("Prim_Int", new Prim_Int());
    pairs ~= new VarTypePair("Prim_Long", new Prim_Long());
    pairs ~= new VarTypePair("Prim_Byte", new Prim_Byte());
    pairs ~= new VarTypePair("Prim_Short", new Prim_Short());
    auto str = new Struct("myStruct", pairs);
    assert(str.getPackedSize() == 15);
    assert(str.getAlignedSize() == first.sizeof);
    assert(str.getOffsetOfSubpart(0) == first.x.offsetof);
    assert(str.getOffsetOfSubpart(1) == first.w.offsetof);
    assert(str.getOffsetOfSubpart(2) == first.z.offsetof);
    assert(str.getOffsetOfSubpart(3) == first.y.offsetof);
    struct complex
    {
        long w;
        long ww;
        int x;
        first f;
        short y;
        byte z;
    }
    pairs = [];
    pairs ~= new VarTypePair("Prim_Long", new Prim_Long());
    pairs ~= new VarTypePair("Prim_Long", new Prim_Long());
    pairs ~= new VarTypePair("Prim_Int", new Prim_Int());
    pairs ~= new VarTypePair("complex", str);
    pairs ~= new VarTypePair("Prim_Short", new Prim_Short());
    pairs ~= new VarTypePair("Prim_Byte", new Prim_Byte());
    auto complexStr = new Struct("yourStruct", pairs);
    assert(complexStr.getPackedSize() == 38);
    assert(complexStr.getAlignedSize() == complex.sizeof);
    assert(complexStr.getOffsetOfSubpart(0) == complex.w.offsetof);
    assert(complexStr.getOffsetOfSubpart(1) == complex.ww.offsetof);
    assert(complexStr.getOffsetOfSubpart(2) == complex.x.offsetof);
    assert(complexStr.getOffsetOfSubpart(3) == complex.f.offsetof);
    assert(complexStr.getOffsetOfSubpart(4) == complex.y.offsetof);
    assert(complexStr.getOffsetOfSubpart(5) == complex.z.offsetof);
    struct superComplex
    {
        long w;
        complex c;
        long ww;
        int x;
        first f;
        short y;
        complex cc;
        byte z;
    }
    pairs = [];
    pairs ~= new VarTypePair("Prim_Long", new Prim_Long());
    pairs ~= new VarTypePair("complex", complexStr);
    pairs ~= new VarTypePair("Prim_Long", new Prim_Long());
    pairs ~= new VarTypePair("Prim_Int", new Prim_Int());
    pairs ~= new VarTypePair("complex", str);
    pairs ~= new VarTypePair("Prim_Short", new Prim_Short());
    pairs ~= new VarTypePair("complex", complexStr);
    pairs ~= new VarTypePair("Prim_Byte", new Prim_Byte());
    auto superComplexStr = new Struct("theirStruct", pairs);
    assert(superComplexStr.getPackedSize() == 114);
    assert(superComplexStr.getAlignedSize() == superComplex.sizeof);
    assert(superComplexStr.getOffsetOfSubpart(0) == superComplex.w.offsetof);
    assert(superComplexStr.getOffsetOfSubpart(1) == superComplex.c.offsetof);
    assert(superComplexStr.getOffsetOfSubpart(2) == superComplex.ww.offsetof);
    assert(superComplexStr.getOffsetOfSubpart(3) == superComplex.x.offsetof);
    assert(superComplexStr.getOffsetOfSubpart(4) == superComplex.f.offsetof);
    assert(superComplexStr.getOffsetOfSubpart(5) == superComplex.y.offsetof);
    assert(superComplexStr.getOffsetOfSubpart(6) == superComplex.cc.offsetof);
    assert(superComplexStr.getOffsetOfSubpart(7) == superComplex.z.offsetof);
}

class VariantConstructor
{
    const string typename;
    const VarTypePair[] consTypes;
    private const TupleType tupleOfConsTypes;

    this (string typename, VarTypePair[] consTypes)
    {
        this.typename = typename;
        this.consTypes = consTypes;
        this.tupleOfConsTypes = new TupleType(consTypes);
    }

    string getTypename() const
    {
        return typename;
    }

    uint getAlignedSize() const
    {
        return tupleOfConsTypes.getAlignedSize();
    }

    uint getPackedSize() const
    {
        return tupleOfConsTypes.getPackedSize();
    }

    uint getLargestPrimSize() const
    {
        return tupleOfConsTypes.getLargestPrimSize();
    }

    uint getOffsetOfSubpart(uint index) const
    {
        return tupleOfConsTypes.getOffsetOfSubpart(index);
    }
}

class VariantType : Type
{
    const string typename;
    const VariantConstructor[] varCons;
    const TypeID id;

    this (const string typename, const VariantConstructor[] varCons)
    {
        this.typename = typename;
        this.varCons = varCons;
        this.id = TypeID.VARIANT;
    }

    string getTypename() const
    {
        return typename;
    }

    uint getAlignedSize() const
    {
        return reduce!((a, b) => max(a, b.getAlignedSize()))(0, varCons);
    }

    uint getPackedSize() const
    {
        return reduce!((a, b) => max(a, b.getPackedSize()))(0, varCons);
    }

    uint getLargestPrimSize() const
    {
        return reduce!((a, b) => max(a, b.getLargestPrimSize()))(0, varCons);
    }

    TypeID getTypeID() const
    {
        return TypeID.VARIANT;
    }

    uint getOffsetOfTypeInCons(uint consIndex, uint typeIndex)
    {
        return varCons[consIndex].getOffsetOfSubpart(typeIndex);
    }
}
