import std.stdio;
import std.string;
import std.conv;
import std.algorithm;
import std.array;
import parser;
import visitor;

immutable uint PTR_SIZE = 4;

interface Type
{
    // The size of the type, if each component of the type were aligned
    // according to the C alignment rules.
    uint getAlignedSize() const;
    // The minimum size required to store the type. The sum total number of
    // bytes of each sub component, ignoring alignment
    uint getPackedSize() const;
    // The number of bytes that the largest primitive type takes up in a
    // composed type. Will descend into the type recursively, so if this is
    // called on a struct that contains structs that contain structs, it will
    // descend into the deepest parts of the type and find the biggest
    // primitive out of all of them
    uint getLargestPrimSize() const;
    // Get the total number of sub parts that compose this type. Basic types
    // of only a single element yield 1
    uint getNumSubparts() const;
    // The offset from 0 that the sub component at 'index' would start in bytes
    // assuming alignment rules. The first component will always be 0, and the
    // second component would be (sizeof(component(0)) + padding)
    uint getOffsetOfSubpart(uint index) const;
    // Return the type object residing at the given index. If this type is
    // a primitive type, then index 0 is 'this'. Accesses out of range should
    // fail
    Type getTypeOfSubpart(uint index) const;
    // Returns true if this type is a complex type, that is, not a primitive
    // type and can conceivably have multiple subparts. True for structs,
    // variants, tuples, etc., false for primitive types and primitives with
    // levels of indirection (pointers)
    bool isComposition() const;
    // True if the element is an indirection type
    bool isIndirection() const;
}

interface NamedType : Type
{
    string getTypename() const;
}

string createPrimitiveType(string name, uint size)
{
    string def = "";
    def ~= `class Prim_` ~ name.capitalize() ~ ` : NamedType {`         ~ "\n";
    def ~= `    string getTypename() const`                             ~ "\n";
    def ~= `    { return "` ~ name ~ `"; }`                             ~ "\n";
    def ~= `    uint getAlignedSize() const`                            ~ "\n";
    def ~= `    { return ` ~ size.to!string ~ `; }`                     ~ "\n";
    def ~= `    uint getPackedSize() const`                             ~ "\n";
    def ~= `    { return ` ~ size.to!string ~ `; }`                     ~ "\n";
    def ~= `    uint getLargestPrimSize() const`                        ~ "\n";
    def ~= `    { return ` ~ size.to!string ~ `; }`                     ~ "\n";
    def ~= `    uint getNumSubparts() const`                            ~ "\n";
    def ~= `    { return 1; }`                                          ~ "\n";
    def ~= `    uint getOffsetOfSubpart(uint index) const`              ~ "\n";
    def ~= `    in { assert(index == 0); }`                             ~ "\n";
    def ~= `    body { return 0; }`                                     ~ "\n";
    def ~= `    Type getTypeOfSubpart(uint index) const`                ~ "\n";
    def ~= `    in { assert(index == 0); }`                             ~ "\n";
    def ~= `    body { return cast(Type)this; }`                        ~ "\n";
    def ~= `    bool isComposition() const`                             ~ "\n";
    def ~= `    { return false; }`                                      ~ "\n";
    def ~= `    bool isIndirection() const`                             ~ "\n";
    def ~= `    { return false; }`                                      ~ "\n";
    def ~= `}`                                                          ~ "\n";
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

enum IndTag
{
    PTR,
    ARR,
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

class ArrInd : Ind
{
    IndTag getInd() const
    {
        return IndTag.ARR;
    }

    string indString() const
    {
        return "[{static}]";
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
        return "[{dynamic}]";
    }
}

class HashInd : Ind
{
    NamedType indexType;

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
class IndType : NamedType
{
    // This kind of indirection
    const Ind ind;
    // The type this level of indirection is pointing to or working with.
    // So if this type is representing *[][]int, then ind would be PtrInd,
    // and 'type' would be an IndirectionType representing [][]int
    const NamedType type;

    this (Ind ind, NamedType type)
    {
        this.ind = ind;
        this.type = type;
    }

    bool isIndirection() const
    {
        return true;
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

    uint getNumSubparts() const
    {
        return 1;
    }

    uint getOffsetOfSubpart(uint index) const
    in
    {
        assert(index == 0);
    }
    body
    {
        return 0;
    }

    Type getTypeOfSubpart(uint index) const
    in
    {
        assert(index == 0);
    }
    body
    {
        return cast(Type)this;
    }

    bool isComposition() const
    {
        return false;
    }

    string getTypename() const
    {
        return ind.indString() ~ type.getTypename();
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
            // If the type is a composition, we need only align the type
            // with the alignment requirements of its largest primitive member
            if (aggregate.access!(aggIndex)(i).isComposition())
            {
                curAlignSize = aggregate.access!(aggIndex)(i)
                                        .getLargestPrimSize();
            }
            // Otherwise, the type is a primitive type, and we just need to
            // get its total size, which will also be its alignment
            // requirements
            else
            {
                curAlignSize = aggregate.access!(aggIndex)(i)
                                        .getAlignedSize();
            }
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
        // Any added end padding necessary before the element offset is reached
        if (aggregate.access!(aggIndex)(index).isComposition())
        {
            finalAlignSize = aggregate.access!(aggIndex)(index)
                                    .getLargestPrimSize();
        }
        else
        {
            finalAlignSize = aggregate.access!(aggIndex)(index)
                                    .getAlignedSize();
        }
        totalBytes += calcPadding(totalBytes, finalAlignSize);
        return totalBytes;
    }

    // Get the total size of this type if every member is properly aligned
    // in memory
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
            // If the type is a composition, we need only align the type
            // with the alignment requirements of its largest primitive member
            if (aggregate.access!(aggIndex)(i).isComposition())
            {
                curAlignSize = aggregate.access!(aggIndex)(i)
                                        .getLargestPrimSize();
            }
            // Otherwise, the type is a primitive type, and we just need to
            // get its total size, which will also be its alignment
            // requirements
            else
            {
                curAlignSize = aggregate.access!(aggIndex)(i)
                                        .getAlignedSize();
            }
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

class TypeTuple : Type
{
    const Type[] tuple;

    this (const Type[] tuple)
    {
        this.tuple = tuple;
    }

    this (VarTypePair[] typePairs)
    {
        const(Type)[] types;
        foreach (typePair; typePairs)
        {
            types ~= typePair.getType();
        }
        this.tuple = types;
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

    bool isComposition() const
    {
        return true;
    }

    bool isIndirection() const
    {
        return false;
    }
}

unittest
{
    Type[] types;
    types ~= new Prim_Long();
    types ~= new Prim_Int();
    types ~= new Prim_Short();
    types ~= new Prim_Byte();
    auto tuple = new TypeTuple(types);
    assert(tuple.getPackedSize() == 15);
    assert(tuple.getAlignedSize() == 16);
    assert(tuple.getOffsetOfSubpart(0) == 0);
    assert(tuple.getOffsetOfSubpart(1) == 8);
    assert(tuple.getOffsetOfSubpart(2) == 12);
    assert(tuple.getOffsetOfSubpart(3) == 14);
    types = [];
    types ~= new Prim_Byte();
    types ~= new Prim_Long();
    types ~= new Prim_Short();
    types ~= new Prim_Int();
    tuple = new TypeTuple(types);
    assert(tuple.getPackedSize() == 15);
    assert(tuple.getAlignedSize() == 24);
    assert(tuple.getOffsetOfSubpart(0) == 0);
    assert(tuple.getOffsetOfSubpart(1) == 8);
    assert(tuple.getOffsetOfSubpart(2) == 16);
    assert(tuple.getOffsetOfSubpart(3) == 20);
    types = [];
    types ~= new Prim_Byte();
    types ~= new Prim_Long();
    types ~= new Prim_Byte();
    types ~= new Prim_Short();
    types ~= new Prim_Byte();
    types ~= new Prim_Int();
    tuple = new TypeTuple(types);
    assert(tuple.getPackedSize() == 17);
    assert(tuple.getAlignedSize() == 32);
    assert(tuple.getOffsetOfSubpart(0) == 0);
    assert(tuple.getOffsetOfSubpart(1) == 8);
    assert(tuple.getOffsetOfSubpart(2) == 16);
    assert(tuple.getOffsetOfSubpart(3) == 18);
    assert(tuple.getOffsetOfSubpart(4) == 20);
    assert(tuple.getOffsetOfSubpart(5) == 24);
}

class Struct : NamedType
{
    const string typename;
    const VarTypePair[] varTypePairs;

    this (const string typename, const VarTypePair[] varTypePairs)
    {
        this.typename = typename;
        this.varTypePairs = varTypePairs;
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

    bool isComposition() const
    {
        return true;
    }

    bool isIndirection() const
    {
        return false;
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
    assert(str.getOffsetOfSubpart(0) == 0);
    assert(str.getOffsetOfSubpart(1) == 8);
    assert(str.getOffsetOfSubpart(2) == 16);
    assert(str.getOffsetOfSubpart(3) == 18);
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
    assert(complexStr.getOffsetOfSubpart(0) == 0);
    assert(complexStr.getOffsetOfSubpart(1) == 8);
    assert(complexStr.getOffsetOfSubpart(2) == 16);
    assert(complexStr.getOffsetOfSubpart(3) == 24);
    assert(complexStr.getOffsetOfSubpart(4) == 48);
    assert(complexStr.getOffsetOfSubpart(5) == 50);
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
    assert(superComplexStr.getOffsetOfSubpart(0) == 0);
    assert(superComplexStr.getOffsetOfSubpart(1) == 8);
    assert(superComplexStr.getOffsetOfSubpart(2) == 64);
    assert(superComplexStr.getOffsetOfSubpart(3) == 72);
    assert(superComplexStr.getOffsetOfSubpart(4) == 80);
    assert(superComplexStr.getOffsetOfSubpart(5) == 104);
    assert(superComplexStr.getOffsetOfSubpart(6) == 112);
    assert(superComplexStr.getOffsetOfSubpart(7) == 168);
}

class VariantConstructor
{
    const string typename;
    const VarTypePair[] consTypes;
    private const TypeTuple tupleOfConsTypes;

    this (string typename, VarTypePair[] consTypes)
    {
        this.typename = typename;
        this.consTypes = consTypes;
        this.tupleOfConsTypes = new TypeTuple(consTypes);
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

class Variant
{
    const string typename;
    const VariantConstructor[] varCons;

    this (const string typename, const VariantConstructor[] varCons)
    {
        this.typename = typename;
        this.varCons = varCons;
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

    uint getOffsetOfTypeInCons(uint consIndex, uint typeIndex)
    {
        return varCons[consIndex].getOffsetOfSubpart(typeIndex);
    }
}

int main(string[] argv)
{
    return 0;
}
