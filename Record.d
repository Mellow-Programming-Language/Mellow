import std.stdio;
import std.variant;
import std.algorithm;
import std.conv;
import std.range;
import std.array;
import parser;
import visitor;
import SymTab;
import ASTUtils;
import typedecl;

// TODO:
//   In the UserTypeNode visit function, there is an unaddressed bug.
//

class RecordBuilder : Visitor
{
    string id;
    string[] templateParams;
    StructMember[] structMemberList;
    VariantMember[] variantMemberList;
    bool[string] usedTypes;
    bool[string] definedTypes;
    StructType*[string] structDefs;
    VariantType*[string] variantDefs;

    mixin TypeVisitors;

    this (ProgramNode node)
    {
        writeln("RecordBuilder: this()");
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

    private auto collectMultiples(T)(T[] elems)
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

    private auto collectStructs(ASTNode node)
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
            writeln("  ", collectMultiples(names));
        }
        writeln(names);
        return structs;
    }

    private auto collectVariants(ASTNode node)
    {
        alias searchStructDef = search!(
            a => typeid(a) == typeid(VariantDefNode)
        );
        auto getVariantName(ASTNonTerminal structDef)
        {
            auto idNode = cast(ASTNonTerminal)structDef.children[0];
            return (cast(ASTTerminal)idNode.children[0]).token;
        }
        auto structs = searchStructDef.findAll(node)
                                      .map!(a => cast(ASTNonTerminal)a).array;
        auto names = structs.map!getVariantName.array;
        if (names.length != names.uniq.array.length)
        {
            writeln("Multiple definitions:");
            writeln("  ", collectMultiples(names));
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
