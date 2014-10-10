import std.stdio;
import std.variant;
import std.algorithm;
import std.conv;
import std.range;
import std.array;
import parser;
import visitor;
import typeInfo;
import SymTab;
import ASTUtils;

// TODO:
//   In the UserTypeNode visit function, there is an unaddressed bug.
//
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

class RecordBuilder : Visitor
{
    string id;
    string[] templateParams;
    Type*[] builderStack;
    StructMember[] structMemberList;
    VariantMember[] variantMemberList;
    bool[string] usedTypes;
    bool[string] definedTypes;
    StructType*[string] structDefs;
    VariantType*[string] variantDefs;

    this (ProgramNode node)
    {
        auto structs = collectStructs(node);
        auto variants = collectVariants(node);
        auto printVisitor = new PrintVisitor();
        printVisitor.visit(cast(ProgramNode)node);
        foreach (structDef; structs)
        {
            visit(cast(StructDefNode)structDef);
        }
        foreach (variantDef; variants)
        {
            visit(cast(VariantDefNode)variantDef);
        }
    }

    auto collectStructs(ASTNode node)
    {
        alias searchStructDef = search!(
            a => typeid(a) == typeid(StructDefNode)
        );
        auto getStructName(ASTNonTerminal structDef)
        {
            auto idNode = cast(ASTNonTerminal)structDef.children[0];
            return (cast(ASTTerminal)idNode.children[0]).token;
        }
        auto structs = searchStructDef.findAll(node)
                                      .map!(a => cast(ASTNonTerminal)a).array;
        auto names = structs.map!getStructName.array;
        if (names.length != names.uniq.array.length)
        {
            writeln("Multiple definitions:");
            writeln("  ", names.collectMultiples);
        }
        writeln(names);
        return structs;
    }

    auto collectVariants(ASTNode node)
    {
        alias searchStructDef = search!(
            a => typeid(a) == typeid(VariantDefNode)
        );
        auto getStructName(ASTNonTerminal structDef)
        {
            auto idNode = cast(ASTNonTerminal)structDef.children[0];
            return (cast(ASTTerminal)idNode.children[0]).token;
        }
        auto structs = searchStructDef.findAll(node)
                                      .map!(a => cast(ASTNonTerminal)a).array;
        auto names = structs.map!getStructName.array;
        if (names.length != names.uniq.array.length)
        {
            writeln("Multiple definitions:");
            writeln("  ", names.collectMultiples);
        }
        writeln(names);
        return structs;
    }

    void visit(StructDefNode node)
    {
        node.children[0].accept(this);
        string structName = id;
        definedTypes[structName] = true;
        node.children[2].accept(this);
        auto structDef = new StructType();
        structDef.name = structName;
        node.children[1].accept(this);
        if (templateParams.length > 0)
        {
            structDef.templateParams = templateParams;
            templateParams = [];
        }
        structDef.members = structMemberList;
        structMemberList = [];
        if (structName in structDefs)
        {
            writeln("Multiple definitions for ", structName);
        }
        structDefs[structName] = structDef;
    }

    void visit(StructBodyNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(StructEntryNode node)
    {
        node.children[0].accept(this);
        string memberName = id;
    }

    void visit(VariableTypePairNode node)
    {
        node.children[0].accept(this);
        string memberName = id;
        node.children[1].accept(this);
        auto member = StructMember();
        member.name = memberName;
        member.type = builderStack[$-1];
        structMemberList ~= member;
        builderStack = [];
    }

    void visit(VariantDefNode node)
    {
        node.children[0].accept(this);
        string variantName = id;
        definedTypes[variantName] = true;
        node.children[2].accept(this);
        auto variantDef = new VariantType();
        variantDef.name = variantName;
        node.children[1].accept(this);
        if (templateParams.length > 0)
        {
            variantDef.templateParams = templateParams;
            templateParams = [];
        }
        variantDef.members = variantMemberList;
        variantMemberList = [];
        if (variantName in variantDefs)
        {
            writeln("Multiple definitions for ", variantName);
        }
        variantDefs[variantName] = variantDef;
    }

    void visit(VariantBodyNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(VariantEntryNode node)
    {
        node.children[0].accept(this);
        string constructorName = id;
        if (node.children.length > 1)
        {
            node.children[1].accept(this);
        }
        auto variantMember = VariantMember();
        variantMember.constructorName = constructorName;
        variantMember.constructorElems = builderStack;
        builderStack = [];
        variantMemberList ~= variantMember;
    }

    void visit(VariantVarDeclListNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

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
        builderStack ~= builder;
    }

    void visit(ArrayTypeNode node)
    {
        node.children[0].accept(this);
        auto array = new ArrayType();
        array.arrayType = builderStack[$-1];
        auto type = new Type();
        type.tag = TypeEnum.ARRAY;
        type.array = array;
        builderStack = builderStack[0..$-1] ~ type;
    }

    void visit(SetTypeNode node)
    {
        node.children[0].accept(this);
        auto set = new SetType();
        set.setType = builderStack[$-1];
        auto type = new Type();
        type.tag = TypeEnum.SET;
        type.set = set;
        builderStack = builderStack[0..$-1] ~ type;
    }

    void visit(HashTypeNode node)
    {
        node.children[0].accept(this);
        node.children[1].accept(this);
        auto hash = new HashType();
        hash.keyType = builderStack[$-2];
        hash.valueType = builderStack[$-1];
        auto type = new Type();
        type.tag = TypeEnum.HASH;
        type.hash = hash;
        builderStack = builderStack[0..$-2] ~ type;
    }

    void visit(UserTypeNode node)
    {
        node.children[0].accept(this);
        string userTypeName = id;
        usedTypes[userTypeName] = true;
        auto aggregate = new AggregateType();
        aggregate.typeName = userTypeName;
        if (node.children.length > 1)
        {
            node.children[1].accept(this);
            // BROKEN BELOW ****************************************************
            // This code segment assumes that the builder stack was previously
            // empty before the line "node.children[1].accept(this);" above was
            // invoked. That invocation populates the builderStack with types
            // that come from a template instantiation, but this could be a
            // recursively defined template instantiation, where we're
            // instantating a templated type that is itself a type used to
            // instantiate a larger template, and thus, perhaps due to this or
            // any other failure condition, the builder stack may not be empty
            // when that line is invoked, so assigning the entire builderStack
            // to type.templateInstantiations here, and then clearing it, is
            // clearly broken
            aggregate.templateInstantiations = builderStack;
            builderStack = [];
            // BROKEN ABOVE ****************************************************
        }
        auto type = new Type();
        type.tag = TypeEnum.AGGREGATE;
        type.aggregate = aggregate;
        builderStack ~= type;
    }

    void visit(IdentifierNode node)
    {
        id = (cast(ASTTerminal)node.children[0]).token;
    }

    void visit(TemplateTypeParamsNode node)
    {
        if (node.children.length > 0)
        {
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
        if (typeid(node.children[0]) == typeid(LambdaNode))
        {
            "A lambda expression cannot be an instantiator for a templated\n"
            "  type; a lambda expression can only be the instantiator for a\n"
            "  templated function".writeln;
        }
        else
        {
            node.children[0].accept(this);
        }
    }

    void visit(ProgramNode node) {}
    void visit(FuncDefNode node) {}
    void visit(FuncSignatureNode node) {}
    void visit(FuncBodyBlocksNode node) {}
    void visit(BareBlockNode node) {}
    void visit(StatementNode node) {}
    void visit(ReturnStmtNode node) {}
    void visit(BoolExprNode node) {}
    void visit(OrTestNode node) {}
    void visit(AndTestNode node) {}
    void visit(NotTestNode node) {}
    void visit(ComparisonNode node) {}
    void visit(ExprNode node) {}
    void visit(OrExprNode node) {}
    void visit(XorExprNode node) {}
    void visit(AndExprNode node) {}
    void visit(ShiftExprNode node) {}
    void visit(SumExprNode node) {}
    void visit(ProductExprNode node) {}
    void visit(ValueNode node) {}
    void visit(NumberNode node) {}
    void visit(IntNumNode node) {}
    void visit(FloatNumNode node) {}
    void visit(CharLitNode node) {}
    void visit(StringLitNode node) {}
    void visit(DeclarationNode node) {}
    void visit(DeclTypeInferNode node) {}
    void visit(CharRangeNode node) {}
    void visit(IntRangeNode node) {}
    void visit(ValueTupleNode node) {}
    void visit(LorRValueNode node) {}
    void visit(LorRTrailerNode node) {}
    void visit(LorRMemberAccessNode node) {}
    void visit(ParenExprNode node) {}
    void visit(ArrayLiteralNode node) {}
    void visit(LambdaNode node) {}
    void visit(LambdaArgsNode node) {}
    void visit(BooleanLiteralNode node) {}
    void visit(CompOpNode node) {}
    void visit(SumOpNode node) {}
    void visit(FuncDefArgListNode node) {}
    void visit(FuncSigArgNode node) {}
    void visit(SpNode node) {}
    void visit(StructFunctionNode node) {}
    void visit(FuncReturnTypeNode node) {}
    void visit(InBlockNode node) {}
    void visit(OutBlockNode node) {}
    void visit(ReturnModBlockNode node) {}
    void visit(BodyBlockNode node) {}
    void visit(StorageClassNode node) {}
    void visit(RefClassNode node) {}
    void visit(ConstClassNode node) {}
    void visit(InterfaceDefNode node) {}
    void visit(InterfaceBodyNode node) {}
    void visit(InterfaceEntryNode node) {}
    void visit(IfStmtNode node) {}
    void visit(ElseIfsNode node) {}
    void visit(ElseIfStmtNode node) {}
    void visit(ElseStmtNode node) {}
    void visit(WhileStmtNode node) {}
    void visit(ForStmtNode node) {}
    void visit(ForInitNode node) {}
    void visit(ForConditionalNode node) {}
    void visit(ForPostExpressionNode node) {}
    void visit(ForeachStmtNode node) {}
    void visit(ForeachArgsNode node) {}
    void visit(SpawnStmtNode node) {}
    void visit(YieldStmtNode node) {}
    void visit(ChanWriteNode node) {}
    void visit(FuncCallNode node) {}
    void visit(DeclAssignmentNode node) {}
    void visit(AssignExistingNode node) {}
    void visit(AssignExistingOpNode node) {}
    void visit(AssignmentNode node) {}
    void visit(CondAssignmentsNode node) {}
    void visit(CondAssignNode node) {}
    void visit(SliceLengthSentinelNode node) {}
    void visit(ChanReadNode node) {}
    void visit(TrailerNode node) {}
    void visit(DynArrAccessNode node) {}
    void visit(TemplateInstanceMaybeTrailerNode node) {}
    void visit(FuncCallTrailerNode node) {}
    void visit(SlicingNode node) {}
    void visit(SingleIndexNode node) {}
    void visit(IndexRangeNode node) {}
    void visit(StartToIndexRangeNode node) {}
    void visit(IndexToEndRangeNode node) {}
    void visit(IndexToIndexRangeNode node) {}
    void visit(FuncCallArgListNode node) {}
    void visit(DotAccessNode node) {}
    void visit(MatchStmtNode node) {}
    void visit(MatchExprNode node) {}
    void visit(MatchWhenNode node) {}
    void visit(MatchWhenExprNode node) {}
    void visit(MatchDefaultNode node) {}
    void visit(VariableTypePairTupleNode node) {}
    void visit(IdTupleNode node) {}
    void visit(ChanTypeNode node) {}
    void visit(TypeTupleNode node) {}
    void visit(ASTTerminal node) {}
}

auto collectMultiples(T)(T[] elems)
{
    bool[T] found;
    bool[T] multiples;
    foreach (elem; elems)
    {
        if (elem in found)
        {
            multiples[elem] = true;
        }
        found[elem] = true;
    }
    return multiples.keys;
}

int main(string[] argv)
{
    string line = "";
    string source = "";
    while ((line = stdin.readln) !is null)
    {
        source ~= line;
    }
    auto parser = new Parser(source);
    auto topNode = parser.parse();
    if (topNode !is null)
    {
        auto vis = new RecordBuilder(cast(ProgramNode)topNode);
        foreach (structDef; vis.structDefs.values)
        {
            structDef.print();
            if (structDef.templateParams.length > 0)
            {
                Type*[string] mapping;
                auto t = new Type();
                t.tag = TypeEnum.LONG;
                mapping["T"] = t;
                structDef.instantiate(mapping);
                structDef.print();
            }
        }
        foreach (variantDef; vis.variantDefs.values)
        {
            variantDef.print();
        }
    }
    else
    {
        writeln("Failed to parse!");
    }
    return 0;
}
