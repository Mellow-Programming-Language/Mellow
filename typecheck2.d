import std.stdio;
import std.variant;
import std.algorithm;
import std.range;
import std.array;
import parser;
import visitor;
import typeInfo;
import TypecheckPrintVisitor;

enum Grain
{
    NAME,
    POINTER,
    DYN_ARR,
    HASH,
    PRIM_TYPE,
    STRUCT,
    VARIANT,
    TUPLE,
    CHAN,
    TEMPLATE
}

struct TypeEntry
{
    private Grain tag;

    union
    {
        string name;
        Type primitive;
        Struct structType;
        VariantType variantType;
        TupleOf tuple;
        PointerTo pointerTo;
        DynArrOf arrayOf;
        HashWith hashWith;
        ChanOf chanOf;
        TemplateInstanceOf templateOf;
    }

    this (TypeEntry entry)
    {
        this.tag = entry.tag;
        final switch (tag)
        {
        case Grain.NAME:
            this.name = entry.name;
            break;
        case Grain.PRIM_TYPE:
            this.primitive = entry.primitive;
            break;
        case Grain.STRUCT:
            this.structType = entry.structType;
            break;
        case Grain.VARIANT:
            this.variantType = entry.variantType;
            break;
        case Grain.TUPLE:
            this.tuple = entry.tuple;
            break;
        case Grain.POINTER:
            this.pointerTo = entry.pointerTo;
            break;
        case Grain.DYN_ARR:
            this.arrayOf = entry.arrayOf;
            break;
        case Grain.HASH:
            this.hashWith = entry.hashWith;
            break;
        case Grain.CHAN:
            this.chanOf = entry.chanOf;
            break;
        case Grain.TEMPLATE:
            this.templateOf = entry.templateOf;
            break;
        }
    }

    this (string name)
    {
        this.name = name;
        this.tag = Grain.NAME;
    }

    this (Type primitive)
    {
        this.primitive = primitive;
        this.tag = Grain.PRIM_TYPE;
    }

    this (Struct structType)
    {
        this.structType = structType;
        this.tag = Grain.STRUCT;
    }

    this (VariantType variantType)
    {
        this.variantType = variantType;
        this.tag = Grain.VARIANT;
    }

    this (TupleOf tuple)
    {
        this.tuple = tuple;
        this.tag = Grain.TUPLE;
    }

    this (PointerTo pointerTo)
    {
        this.pointerTo = pointerTo;
        this.tag = Grain.POINTER;
    }

    this (DynArrOf arrayOf)
    {
        this.arrayOf = arrayOf;
        this.tag = Grain.DYN_ARR;
    }

    this (HashWith hashWith)
    {
        this.hashWith = hashWith;
        this.tag = Grain.HASH;
    }

    this (ChanOf chanOf)
    {
        this.chanOf = chanOf;
        this.tag = Grain.CHAN;
    }

    this (TemplateInstanceOf templateOf)
    {
        this.templateOf = templateOf;
        this.tag = Grain.TEMPLATE;
    }

    auto getTag()
    {
        return tag;
    }

    string getTypename()
    {
        final switch (tag)
        {
        case Grain.NAME:
            return name;
        case Grain.PRIM_TYPE:
            return primitive.getTypename();
        case Grain.STRUCT:
            return structType.getTypename();
        case Grain.VARIANT:
            return variantType.getTypename();
        case Grain.TUPLE:
            return tuple.getTypename();
        case Grain.POINTER:
            return pointerTo.getTypename();
        case Grain.DYN_ARR:
            return arrayOf.getTypename();
        case Grain.HASH:
            return hashWith.getTypename();
        case Grain.CHAN:
            return chanOf.getTypename();
        case Grain.TEMPLATE:
            return templateOf.getTypename();
        }
    }
}

TypeEntry[string] g_types;

void printAllTypes()
{
    foreach (type; g_types.byKey())
    {
        writeln(type, ": ", g_types[type].getTypename());
    }
}

static this()
{
    g_types["double"] = TypeEntry(new Prim_Double());
    g_types["float"]  = TypeEntry(new Prim_Float());
    g_types["long"]   = TypeEntry(new Prim_Long());
    g_types["ulong"]  = TypeEntry(new Prim_Ulong());
    g_types["int"]    = TypeEntry(new Prim_Int());
    g_types["uint"]   = TypeEntry(new Prim_Uint());
    g_types["short"]  = TypeEntry(new Prim_Short());
    g_types["ushort"] = TypeEntry(new Prim_Ushort());
    g_types["byte"]   = TypeEntry(new Prim_Byte());
    g_types["ubyte"]  = TypeEntry(new Prim_Ubyte());
    g_types["char"]   = TypeEntry(new Prim_Char());
    g_types["bool"]   = TypeEntry(new Prim_Bool());
    g_types["string"] = TypeEntry(new Prim_String());
}

struct TemplateInstanceOf
{
    private string instantiatedType;
    private string templateParamTuple;

    this (string instantiatedType, string templateParamTuple)
    {
        this.instantiatedType = instantiatedType;
        this.templateParamTuple = templateParamTuple;
    }

    string getInstantiatedType()
    {
        return this.instantiatedType;
    }

    string getTemplateParamTuple()
    {
        return this.templateParamTuple;
    }

    string getTypename()
    in
    {
        assert(instantiatedType in g_types);
        assert(templateParamTuple in g_types);
    }
    body
    {
        return g_types[instantiatedType].getTypename()
            ~ "!(" ~ g_types[templateParamTuple].getTypename() ~ ")";
    }
}

struct PointerTo
{
    private string pointedType;

    this (string pointedType)
    {
        this.pointedType = pointedType;
    }

    string getTypename()
    in
    {
        assert(pointedType in g_types);
    }
    body
    {
        return "*" ~ g_types[pointedType].getTypename();
    }

    string getPointed()
    {
        return pointedType;
    }
}

struct DynArrOf
{
    private string type;

    this (string type)
    {
        this.type = type;
    }

    string getTypename()
    in
    {
        assert(type in g_types);
    }
    body
    {
        return "[]" ~ g_types[type].getTypename();
    }

    string getArrayOf()
    {
        return type;
    }
}

struct HashWith
{
    private string keyType;
    private string valueType;

    this (string keyType, string valueType)
    {
        this.keyType = keyType;
        this.valueType = valueType;
    }

    string getTypename()
    {
        return "[" ~ g_types[keyType].getTypename() ~ "]"
            ~ g_types[valueType].getTypename();
    }

    string getKeyType()
    {
        return keyType;
    }

    string getValueType()
    {
        return valueType;
    }
}

struct ChanOf
{
    private string chanType;

    this (string chanType)
    {
        this.chanType = chanType;
    }

    string getTypename()
    {
        return "chan!(" ~ g_types[chanType].getTypename() ~ ")";
    }

    string getChanType()
    {
        return chanType;
    }
}

struct TupleOf
{
    private string[] types;

    this (string[] types)
    {
        this.types = types;
    }

    string getTypename()
    {
        return types.join(" ");
    }

    string[] getTypes()
    {
        return types;
    }
}

struct VarTypePair
{
    string typename;
    string identifier;
    StorageClass[] storeClasses;

    this (string typename, string identifier)
    {
        this.typename = typename;
        this.identifier = identifier;
    }

    this (string typename, string identifier, StorageClass[] storeClasses)
    {
        this.typename = typename;
        this.identifier = identifier;
        this.storeClasses = storeClasses;
    }
}

class Scope
{
    VarTypePair[string] typeDecls;
}

class FunctionSignature
{
    string returnType;
    VarTypePair[] params;
}

class TypeAnnotate : Visitor
{
    Scope[] scopes;
    string curId;
    FunctionSignature curFunc;
    string curTypeId;

    void visit(ProgramNode node)
    {
        scopes ~= new Scope();
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(SpNode node) {}
    void visit(StructDefNode node) {}

    void visit(StructEntryNode node) {}
    void visit(StructFunctionNode node) {}
    void visit(FuncDefNode node)
    {
        curFunc = new FunctionSignature();
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(FuncDefArgListNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(FuncSigArgNode node)
    {
        node.children[0].accept(this);
        auto arg = VarTypePair();
        arg.identifier = curId;
        foreach (storeClass; node.children[1..$-1])
        {
            if (typeid(storeClass) == typeid(RefClassNode))
            {
                arg.storeClasses ~= StorageClass.REF;
            }
            else if (typeid(storeClass) == typeid(ConstClassNode))
            {
                arg.storeClasses ~= StorageClass.CONST;
            }
        }
        node.children[$-1].accept(this);
        arg.typename = curTypeId;
        curFunc.params ~= arg;
    }

    void visit(FuncReturnTypeNode node)
    {
        if (node.children.length > 0)
        {
            node.children[0].accept(this);
        }
        curFunc.returnType = curTypeId;
        writeln("curFunc.returnType.name: ", curFunc.returnType);
    }

    void visit(FuncBodyBlocksNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(InBlockNode node) {}
    void visit(OutBlockNode node) {}
    void visit(ReturnModBlockNode node) {}
    void visit(BodyBlockNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(BareBlockNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(StorageClassNode node) {}
    void visit(RefClassNode node) {}
    void visit(ConstClassNode node) {}

    void visit(VariantNode node) {}

    void visit(VariantEntryNode node) {}
    void visit(VariantVarDeclListNode node) {}
    void visit(StatementNode node)
    {
        node.children[0].accept(this);
    }

    void visit(ReturnStmtNode node)
    {
        node.children[0].accept(this);
        if (node.children[0].data["type"].get!string == curFunc.returnType)
        {
            writeln("Return type agrees with return statement type!");
        }
    }

    void visit(IfStmtNode node) {}
    void visit(ElseIfStmtNode node) {}
    void visit(ElseStmtNode node) {}
    void visit(WhileStmtNode node) {}
    void visit(ForStmtNode node) {}
    void visit(ForInitNode node) {}
    void visit(ForeachStmtNode node) {}
    void visit(Foreach1Node node) {}
    void visit(Foreach2Node node) {}
    void visit(DeclAssignmentNode node) {}
    void visit(DeclTypeInferNode node) {}
    void visit(AssignmentStmtNode node) {}
    void visit(DeclarationNode node)
    {
        node.children[0].accept(this);
    }

    void visit(SpawnStmtNode node) {}
    void visit(YieldStmtNode node) {}
    void visit(ChanWriteNode node) {}
    void visit(ChanReadStmtNode node) {}
    void visit(FuncCallComplexNode node) {}
    void visit(FuncCallNode node) {}
    void visit(MemberAccessesNode node) {}
    void visit(MemberAccessNode node) {}
    void visit(BoolExprNode node) {}
    void visit(TrueExprNode node) {}
    void visit(FalseExprNode node) {}
    void visit(ParenExprNode node)
    {
        node.children[0].accept(this);
        node.data["type"] = node.children[0].data["type"];
    }

    void visit(ExprStmtNode node) {}
    void visit(ExprNode node)
    {
        node.children[0].accept(this);
        node.data["type"] = node.children[0].data["type"];
    }

    void visit(MatchStmtNode node) {}
    void visit(MatchCaseNode node) {}
    void visit(RangeMatchNode node) {}
    void visit(MatchIsNode node) {}
    void visit(CharMatchNode node) {}
    void visit(StringMatchNode node) {}
    void visit(NumMatchNode node) {}
    void visit(NumRangeMatchNode node) {}
    void visit(CharRangeMatchNode node) {}
    void visit(VariableTypePairNode node)
    {
        node.children[0].accept(this);
        auto varname = curId;
        node.children[1].accept(this);
        auto typename = curTypeId;
        auto pair = VarTypePair(typename, varname);
        scopes[$-1].typeDecls[varname] = pair;
    }

    void visit(ChanReadNode node) {}
    void visit(SumNode node)
    {
        node.children[0].accept(this);
        node.data["type"] = node.children[0].data["type"];
        if (node.children.length == 1)
        {
            return;
        }
        foreach (child; node.children[2..$].stride(2))
        {
            child.accept(this);
            if (node.data["type"].get!string == child.data["type"].get!string)
            {
                writeln("Expression type agreement!");
            }
            else
            {
                import core.stdc.stdlib;
                exit(0);
            }
        }
    }

    void visit(ProductNode node)
    {
        node.children[0].accept(this);
        node.data["type"] = node.children[0].data["type"];
        if (node.children.length == 1)
        {
            return;
        }
        foreach (child; node.children[2..$].stride(2))
        {
            child.accept(this);
            if (node.data["type"].get!string == child.data["type"].get!string)
            {
                writeln("Expression type agreement!");
            }
            else
            {
                import core.stdc.stdlib;
                exit(0);
            }
        }
    }

    void visit(ValueNode node)
    {
        node.children[0].accept(this);
        node.data["type"] = node.children[0].data["type"];
    }

    void visit(SumOpNode node) {}
    void visit(MulOpNode node) {}
    void visit(NumberNode node)
    {
        node.children[0].accept(this);
        node.data["type"] = node.children[0].data["type"];
    }

    void visit(CharLitNode node)
    {
        node.data["type"] = "char";
    }

    void visit(StringLitNode node)
    {
        node.data["type"] = "string";
    }

    void visit(IntNumNode node)
    {
        node.data["type"] = "int";
    }

    void visit(FloatNumNode node)
    {
        node.data["type"] = "double";
    }

    void visit(IdentifierNode node)
    {
        curId = (cast(ASTTerminal)node.children[0]).token;
    }

    void visit(IdTupleNode node) {}
    void visit(TypeIdNode node)
    {
        node.children[0].accept(this);
    }

    void visit(ChanTypeNode node)
    {
        node.children[0].accept(this);
        auto chan = TypeEntry(ChanOf(curTypeId));
        curTypeId = chan.getTypename();
        if (curTypeId !in g_types)
        {
            g_types[curTypeId] = chan;
        }
    }

    void visit(ArrayTypeNode node)
    {
        node.children[1].accept(this);
        debug (DEBUG) writeln("ArrayTypeNode: curTypeId: ", curTypeId);
        TypeEntry arrayType;
        if (typeid(node.children[0]) == typeid(PointerDeclNode))
        {
            arrayType = TypeEntry(PointerTo(curTypeId));
        }
        else if (typeid(node.children[0]) == typeid(DynArrayDeclNode))
        {
            arrayType = TypeEntry(DynArrOf(curTypeId));
        }
        curTypeId = arrayType.getTypename();
        debug (DEBUG) writeln("  curTypeId: ", curTypeId);
        if (curTypeId !in g_types)
        {
            g_types[curTypeId] = arrayType;
        }
    }

    void visit(PointerDeclNode node)
    {}

    void visit(DynArrayDeclNode node)
    {}

    void visit(SetTypeNode node) {}
    void visit(HashTypeNode node)
    {
        node.children[0].accept(this);
        string keyType = curTypeId;
        node.children[1].accept(this);
        string valueType = curTypeId;
        TypeEntry hashType = TypeEntry(HashWith(keyType, valueType));
        curTypeId = hashType.getTypename();
        if (curTypeId !in g_types)
        {
            g_types[curTypeId] = hashType;
        }
    }

    void visit(TypeTupleNode node)
    {
        string[] types;
        foreach (child; node.children)
        {
            types ~= curTypeId;
        }
        auto tupleType = TypeEntry(TupleOf(types));
        curTypeId = tupleType.getTypename();
        if (curTypeId !in g_types)
        {
            g_types[curTypeId] = tupleType;
        }
    }

    void visit(UserTypeNode node) {}
    void visit(BasicTypeNode node)
    {
        curTypeId = (cast(ASTTerminal)node.children[0]).token;
        debug (DEBUG) writeln("BasicTypeNode: curTypeId: {", curTypeId, "}");
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
        string[] templateTypeTuple;
        foreach (child; node.children)
        {
            child.accept(this);
            templateTypeTuple ~= curTypeId;
        }
        auto tuple = TypeEntry(TupleOf(templateTypeTuple));
        curTypeId = tuple.getTypename();
        if (curTypeId !in g_types)
        {
            g_types[curTypeId] = tuple;
        }
    }

    void visit(TemplateParamSingleNode node)
    {
        node.children[0].accept(this);
    }

    void visit(TemplateIdNode node)
    {
        node.children[0].accept(this);
    }

    void visit(StructBodyNode node) {}
    void visit(VariantBodyNode node) {}
    void visit(ASTTerminal node) {}
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
        auto vis = new TypeAnnotate();
        vis.visit(cast(ProgramNode)topNode);
        auto print = new TypecheckPrintVisitor();
        print.visit(cast(ProgramNode)topNode);
        printAllTypes();
    }
    else
    {
        writeln("Failed to parse!");
    }
    return 0;
}
