import std.stdio;
import std.algorithm;
import std.range;

// TODO:
//   The myriad print() functions in the Type definitions should be converted
//   to string format() functions that simply build and return a string for
//   printing.

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
            foreach (instantiation; templateInstantiations[0..$-1])
            {
                instantiation.print();
                write(", ");
            }
            templateInstantiations[$-1].print();
            write(")");
        }
    }
}

struct TupleType
{
    Type*[] types;

    void print()
    {
        write("(");
        foreach (type; types[0..$-1])
        {
            type.print();
            write(", ");
        }
        types[$-1].print();
        write(")");
    }
}

// Type representing the value that is a callable function pointer
struct FuncPtrType
{
    // The types of the arguments to the function, in the order they appeared
    // in the original argument list
    Type*[] funcArgs;
    // Even if the return type is a tuple, it's still really only a single type
    Type* returnType;
    //Type*[] returnType;
    // Indicates whether this function pointer is a fat pointer, meaning it
    // contains not only the pointer to the function, but an environment
    // pointer to be passed as an argument to the function as well
    bool isFatPtr;

    // The syntax for function pointers is not yet decided, so this is temporary
    void print()
    {
        write("funcptr((");
        if (funcArgs.length > 0)
        {
            foreach (type; funcArgs[0..$-1])
            {
                type.print();
                write(", ");
            }
            funcArgs[$-1].print();
            write("): ");
        }
        returnType.print();
        write(")");
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
    bool refType;
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

    void print()
    {
        final switch (tag)
        {
        case TypeEnum.VOID      : write("void");      break;
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
        case TypeEnum.TUPLE     : tuple.print();      break;
        case TypeEnum.FUNCPTR   : funcPtr.print();    break;
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

    void visit(UserTypeNode node)
    {
        node.children[0].accept(this);
        string userTypeName = id;
        auto aggregate = new AggregateType();
        aggregate.typeName = userTypeName;
        if (node.children.length > 1)
        {
            builderStack.length++;
            node.children[1].accept(this);
            aggregate.templateInstantiations = builderStack[$-1];
            builderStack.length--;
        }
        auto type = new Type();
        type.tag = TypeEnum.AGGREGATE;
        type.aggregate = aggregate;
        builderStack[$-1] ~= type;
    }

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
