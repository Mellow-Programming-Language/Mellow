import std.stdio;
import std.variant;
import std.algorithm;
import std.conv;
import std.range;
import std.array;
import parser;
import visitor;
import ASTUtils;
import typedecl;

class RecordBuilder : Visitor
{
    private string id;
    private StructMember[] structMemberList;
    private VariantMember[] variantMemberList;
    private bool[string] definedTypes;
    StructType*[string] structDefs;
    VariantType*[string] variantDefs;

    mixin TypeVisitors;

    this (ProgramNode node)
    {
        auto structs = collectNodes!StructDefNode(node);
        auto externStructs = collectNodes!ExternStructDeclNode(node);
        auto variants = collectNodes!VariantDefNode(node);
        foreach (structDef; structs)
        {
            builderStack.length++;
            visit(cast(StructDefNode)structDef);
            builderStack.length--;
        }
        foreach (structDecl; externStructs)
        {
            visit(cast(ExternStructDeclNode)structDecl);
        }
        foreach (variantDef; variants)
        {
            builderStack.length++;
            visit(cast(VariantDefNode)variantDef);
            builderStack.length--;
        }
    }

    private auto collectNodes(T)(ASTNode node)
    {
        alias searchDef = search!(
            a => typeid(a) == typeid(T)
        );
        auto getName(ASTNonTerminal def)
        {
            auto idNode = cast(ASTNonTerminal)def.children[0];
            return (cast(ASTTerminal)idNode.children[0]).token;
        }
        auto results = searchDef.findAll(node)
                                .map!(a => cast(ASTNonTerminal)a)
                                .array;
        auto names = results.map!getName.array;
        return results;
    }

    void visit(ExternStructDeclNode node)
    {
        node.children[0].accept(this);
        string structName = id;
        definedTypes[structName] = true;
        auto structDecl = new StructType();
        structDecl.name = structName;
        structDecl.isExtern = true;
        if (structName in structDefs)
        {
            writeln("Multiple definitions for ", structName);
            throw new Exception("Multiple declarations for ", structName);
        }
        structDefs[structName] = structDecl;
    }

    void visit(StructDefNode node)
    {
        node.children[0].accept(this);
        string structName = id;
        definedTypes[structName] = true;
        node.children[2].accept(this);
        auto structDef = new StructType();
        structDef.name = structName;
        structDef.isExtern = false;
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
            throw new Exception("Multiple declarations for ", structName);
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
        member.type = builderStack[$-1][$-1];
        structMemberList ~= member;
        builderStack[$-1] = [];
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
            throw new Exception("Multiple declarations for ", variantName);
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
        auto variantMember = VariantMember();
        variantMember.constructorName = constructorName;
        if (node.children.length > 1)
        {
            auto constructorTypeElems = new TupleType();
            foreach (child; node.children[1..$])
            {
                child.accept(this);
                constructorTypeElems.types ~= builderStack[$-1][$-1];
                builderStack[$-1] = builderStack[$-1][0..$-1];
            }
            auto wrap = new Type();
            wrap.tag = TypeEnum.TUPLE;
            wrap.tuple = constructorTypeElems;
            variantMember.constructorElems = wrap;
        }
        else
        {
            auto voidType = new Type();
            voidType.tag = TypeEnum.VOID;
            variantMember.constructorElems = voidType;
        }
        variantMemberList ~= variantMember;
    }

    void visit(IdentifierNode node)
    {
        id = (cast(ASTTerminal)node.children[0]).token;
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

    void visit(ProgramNode node) {}
    void visit(ExternFuncDeclNode node) {}
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
    void visit(ValueTupleNode node) {}
    void visit(LorRValueNode node) {}
    void visit(LorRTrailerNode node) {}
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
    void visit(MatchWhenNode node) {}
    void visit(PatternNode node) {}
    void visit(DestructVariantPatternNode node) {}
    void visit(StructPatternNode node) {}
    void visit(BoolPatternNode node) {}
    void visit(StringPatternNode node) {}
    void visit(CharPatternNode node) {}
    void visit(IntPatternNode node) {}
    void visit(FloatPatternNode node) {}
    void visit(TuplePatternNode node) {}
    void visit(ArrayPatternNode node) {}
    void visit(ArrayTailPatternNode node) {}
    void visit(WildcardPatternNode node) {}
    void visit(VarOrBareVariantPatternNode node) {}
    void visit(VariableTypePairTupleNode node) {}
    void visit(IdTupleNode node) {}
    void visit(IsExprNode node) {}
    void visit(VariantIsMatchNode node) {}
    void visit(IdOrWildcardNode node) {}
    void visit(ASTTerminal node) {}
}
