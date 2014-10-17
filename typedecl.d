import std.stdio;
import std.algorithm;
import std.range;

// TODO:
//   The myriad print() functions in the Type definitions should be converted
//   to string format() functions that simply build and return a string for
//   printing.

enum TypeEnum
{
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
    STRUCT,
    VARIANT,
}

struct ArrayType
{
    Type* arrayType;

    void print()
    {
        write("[]");
        arrayType.print();
    }
}

struct HashType
{
    Type* keyType;
    Type* valueType;

    void print()
    {
        write("[");
        keyType.print();
        write("]");
        valueType.print();
    }
}

struct SetType
{
    Type* setType;

    void print()
    {
        write("<>");
        setType.print();
    }
}

struct AggregateType
{
    string typeName;
    Type*[] templateInstantiations;

    void print()
    {
        write(typeName);
        if (templateInstantiations.length == 1)
        {
            write("!");
            templateInstantiations[0].print();
        }
        else if (templateInstantiations.length > 1)
        {
            write("!(");
            foreach (instantiation; templateInstantiations)
            {
                instantiation.print();
                write(", ");
            }
            write(")");
        }
    }
}

struct StructMember
{
    string name;
    Type* type;

    void print()
    {
        write(name, " : ");
        type.print();
        writeln(";");
    }
}

struct StructType
{
    string name;
    string[] templateParams;
    StructMember[] members;

    void print()
    {
        write("struct ", name);
        if (templateParams.length > 0)
        {
             write("(", templateParams.join(", "), ")");
        }
        writeln(" {");
        foreach (member; members)
        {
            write("    ");
            member.print;
        }
        writeln("}");
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
        templateParams = [];
    }
}

struct VariantMember
{
    string constructorName;
    Type*[] constructorElems;

    void print()
    {
        write(constructorName);
        if (constructorElems.length > 0)
        {
            write(" (");
            constructorElems[0].print();
            if (constructorElems.length > 1)
            {
                foreach (elem; constructorElems[1..$])
                {
                    write(", ");
                    elem.print();
                }
            }
            write(")");
        }
        writeln();
    }
}

struct VariantType
{
    string name;
    string[] templateParams;
    VariantMember[] members;

    void print()
    {
        write("variant ", name);
        if (templateParams.length > 0)
        {
             write("(", templateParams.join(", "), ")");
        }
        writeln(" {");
        foreach (member; members)
        {
            write("    ");
            member.print;
        }
        writeln("}");
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
            foreach (ref elemType; member.constructorElems)
            {
                descend(elemType);
            }
        }
        templateParams = [];
    }
}

struct Type
{
    TypeEnum tag;
    union {
        ArrayType* array;
        HashType* hash;
        SetType* set;
        AggregateType* aggregate;
        StructType* structDef;
        VariantType* variantDef;
    };

    void print()
    {
        final switch (tag)
        {
        case TypeEnum.LONG      : write("long");      break;
        case TypeEnum.INT       : write("int");       break;
        case TypeEnum.SHORT     : write("short");     break;
        case TypeEnum.BYTE      : write("byte");      break;
        case TypeEnum.FLOAT     : write("float");     break;
        case TypeEnum.DOUBLE    : write("double");    break;
        case TypeEnum.CHAR      : write("char");      break;
        case TypeEnum.BOOL      : write("bool");      break;
        case TypeEnum.STRING    : write("string");    break;
        case TypeEnum.SET       : set.print();        break;
        case TypeEnum.HASH      : hash.print();       break;
        case TypeEnum.ARRAY     : array.print();      break;
        case TypeEnum.AGGREGATE : aggregate.print();  break;
        case TypeEnum.STRUCT    : structDef.print();  break;
        case TypeEnum.VARIANT   : variantDef.print(); break;
        }
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
