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

    void print()
    {
        write(typeName);
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
    StructMember[] members;

    void print()
    {
        writeln("struct ", name, " {");
        foreach (member; members)
        {
            write("    ");
            member.print;
        }
        writeln("}");
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
    VariantMember[] members;

    void print()
    {
        writeln("variant ", name, " {");
        foreach (member; members)
        {
            write("    ");
            member.print;
        }
        writeln("}");
    }
}

class RecordBuilder : Visitor
{
    string id;
    Type*[] builderStack;
    StructMember[] structMemberList;
    VariantMember[] variantMemberList;
    bool[string] usedTypes;
    bool[string] definedTypes;
    StructType*[string] structDefs;
    VariantType*[string] variantDefs;

    void visit(StructDefNode node)
    {
        node.children[0].accept(this);
        string structName = id;
        definedTypes[structName] = true;
        node.children[2].accept(this);
        auto structDef = new StructType();
        structDef.name = structName;
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
        auto type = new Type();
        type.tag = TypeEnum.AGGREGATE;
        type.aggregate = aggregate;
        builderStack ~= type;
    }

    void visit(IdentifierNode node)
    {
        id = (cast(ASTTerminal)node.children[0]).token;
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
    void visit(TemplateInstantiationNode node) {}
    void visit(TemplateParamNode node) {}
    void visit(TemplateParamListNode node) {}
    void visit(TemplateAliasNode node) {}
    void visit(TemplateTypeParamsNode node) {}
    void visit(TemplateTypeParamListNode node) {}
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

auto getConcrete(ASTNonTerminal[] structDefs)
{
    auto nonTerminals = structDefs.map!(a => cast(ASTNonTerminal)a);
    return nonTerminals.filter!(
        a => (cast(ASTNonTerminal)a.children[1]).children.length == 0
    ).array;
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
        // Do struct processing
        auto concreteStructs = topNode.collectStructs.getConcrete;
        auto concreteVariants = topNode.collectVariants.getConcrete;
        writeln(concreteStructs);
        writeln(concreteVariants);
        auto printVisitor = new PrintVisitor();
        printVisitor.visit(cast(ProgramNode)topNode);
        auto vis = new RecordBuilder();
        foreach (structDef; concreteStructs)
        {
            vis.visit(cast(StructDefNode)structDef);
        }
        foreach (structDef; vis.structDefs.values)
        {
            structDef.print();
        }
        foreach (variantDef; concreteVariants)
        {
            vis.visit(cast(VariantDefNode)variantDef);
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
