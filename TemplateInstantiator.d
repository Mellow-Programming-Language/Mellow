import std.stdio;
import std.variant;
import std.algorithm;
import std.conv;
import std.range;
import std.array;
import parser;
import visitor;
import typedecl;
import Record;
import utils;
import FunctionSig;

debug (TEMPLATE_INSTANTIATION_TRACE)
{
    string traceIndent;
    string tracer(string funcName)
    {
        return `
            string mixin_funcName = "` ~ funcName ~ `";
            writeln(traceIndent, "Entered: ", mixin_funcName);
            traceIndent ~= "  ";
            scope(success)
            {
                traceIndent = traceIndent[0..$-2];
                writeln(traceIndent, "Exiting: ", mixin_funcName);
            }
        `;
    }
}

class TemplateInstantiator : Visitor
{
    private string id;
    private uint index;
    private string funcName;
    private Type*[] types;
    private string[] templateParams;
    private string[] funcParams;
    private FuncSig* newSig;

    private auto inFuncParams(string name)
    {
        foreach (str; funcParams)
        {
            if (name == str)
            {
                return true;
            }
        }
        return false;
    }

    private auto getTypeFromPair(string name)
    {
        foreach (str, type; lockstep(funcParams, types))
        {
            if (name == str)
            {
                return type;
            }
        }
        assert(false, "Unreachable");
    }

    auto instantiateFunction(FuncSig* sig, Type*[] types)
    {
        this.newSig = new FuncSig();
        this.newSig.funcName = sig.funcName;
        this.newSig.templateParams = sig.templateParams;
        this.newSig.closureVars = sig.closureVars;
        this.newSig.memberOf = sig.memberOf;
        this.types = types;
        auto node = sig.funcDefNode;
        node = cast(FuncDefNode)node.treecopy;
        node.accept(this);
        this.newSig.funcDefNode = node;
        return this.newSig;
    }

    void visit(IdentifierNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("IdentifierNode"));
        id = (cast(ASTTerminal)node.children[0]).token;
        index = (cast(ASTTerminal)node.children[0]).index;
    }

    void visit(FuncDefNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncDefNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(FuncSignatureNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncSignatureNode"));
        // IdentifierNode
        node.children[0].accept(this);
        // TemplateTypeParamsNode
        node.children[1].accept(this);
        if (templateParams.length != types.length)
        {
            throw new Exception(
                "Mismatch in type params for instantiation of function:\n"
                ~ funcName
            );
        }
        funcParams = templateParams;
        // FuncDefArgListNode
        node.children[2].accept(this);
        // FuncReturnType
        node.children[3].accept(this);
    }

    void visit(TemplateTypeParamsNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("TemplateTypeParamsNode"));
        if (node.children.length == 0)
        {
            throw new Exception(
                "Cannot instantiate untemplated function"
            );
        }
        node.children[0].accept(this);
        node.children = [];
    }

    void visit(TemplateTypeParamListNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("TemplateTypeParamListNode"));
        foreach (child; node.children)
        {
            child.accept(this);
            templateParams ~= id;
        }
    }

    void visit(FuncDefArgListNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncDefArgListNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(FuncSigArgNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncSigArgNode"));
        node.children[$-1].accept(this);
    }

    void visit(FuncReturnTypeNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncReturnTypeNode"));
        node.children[0].accept(this);
    }

    void visit(FuncBodyBlocksNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncBodyBlocksNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(BareBlockNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("BareBlockNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(StatementNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("StatementNode"));
        node.children[0].accept(this);
    }

    void visit(ReturnStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ReturnStmtNode"));
        node.children[0].accept(this);
    }

    void visit(BoolExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("BoolExprNode"));
        node.children[0].accept(this);
    }

    void visit(OrTestNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("OrTestNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(AndTestNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("AndTestNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(NotTestNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("NotTestNode"));
        node.children[0].accept(this);
    }

    void visit(ComparisonNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ComparisonNode"));
        if (node.children.length > 1)
        {
            node.children[0].accept(this);
            node.children[2].accept(this);
        }
    }

    void visit(ExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ExprNode"));
        node.children[0].accept(this);
    }

    void visit(OrExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("OrExprNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(XorExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("XorExprNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(AndExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("AndExprNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(ShiftExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ShiftExprNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(SumExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("SumExprNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(ProductExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ProductExprNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(ValueNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ValueNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(ParenExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ParenExprNode"));
        node.children[0].accept(this);
    }

    void visit(StructConstructorNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("StructConstructorNode"));
        if (cast(TemplateInstantiationNode)node.children[1])
        {
            node.children[1].accept(this);
            for (auto i = 3; i < node.children.length; i += 2)
            {
                node.children[i].accept(this);
            }
        }
        else
        {
            for (auto i = 2; i < node.children.length; i += 2)
            {
                node.children[i].accept(this);
            }
        }
    }

    void visit(StructMemberConstructorNode node) {}

    void visit(ArrayLiteralNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ArrayLiteralNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(VariableTypePairNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("VariableTypePairNode"));
        node.children[1].accept(this);
    }

    void visit(VariableTypePairTupleNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("VariableTypePairTupleNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(DeclarationNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("DeclarationNode"));
        node.children[0].accept(this);
    }

    void visit(DeclAssignmentNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("DeclAssignmentNode"));
        node.children[1].accept(this);
    }

    void visit(AssignExistingNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("AssignExistingNode"));
        node.children[0].accept(this);
        node.children[2].accept(this);
    }

    void visit(DeclTypeInferNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("DeclTypeInferNode"));
        node.children[1].accept(this);
    }

    void visit(AssignmentNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("AssignmentNode"));
        node.children[0].accept(this);
    }

    void visit(ValueTupleNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ValueTupleNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(LorRValueNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("LorRValueNode"));
        if (node.children.length > 1)
        {
            node.children[1].accept(this);
        }
    }

    void visit(LorRTrailerNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("LorRTrailerNode"));
        if (cast(IdentifierNode)node.children[0])
        {
            node.children[1].accept(this);
        }
        else
        {
            foreach (child; node.children)
            {
                child.accept(this);
            }
        }
    }

    void visit(SlicingNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("SlicingNode"));
        node.children[0].accept(this);
    }

    void visit(SingleIndexNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("SingleIndexNode"));
        node.children[0].accept(this);
    }

    void visit(IndexRangeNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("IndexRangeNode"));
        node.children[0].accept(this);
    }

    void visit(StartToIndexRangeNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("StartToIndexRangeNode"));
        node.children[0].accept(this);
    }

    void visit(IndexToEndRangeNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("IndexToEndRangeNode"));
        node.children[0].accept(this);
    }

    void visit(IndexToIndexRangeNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("IndexToIndexRangeNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(TrailerNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("TrailerNode"));
        node.children[0].accept(this);
    }

    void visit(DynArrAccessNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("DynArrAccessNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(TemplateInstanceMaybeTrailerNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("TemplateInstanceMaybeTrailerNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(FuncCallTrailerNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncCallTrailerNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(FuncCallArgListNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncCallArgListNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(FuncCallNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncCallNode"));
        // TODO need to update to allow for calling templated functions

        node.children[1].accept(this);
    }

    void visit(DotAccessNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("DotAccessNode"));
        // TODO update this for when UFCS calls with tmeplated functions are
        // supported

        node.children[1].accept(this);
    }

    void visit(IfStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("IfStmtNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(ElseIfsNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ElseIfsNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(ElseIfStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ElseIfStmtNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(ElseStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ElseStmtNode"));
        if (node.children.length > 0)
        {
            node.children[0].accept(this);
        }
    }

    void visit(WhileStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("WhileStmtNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(CondAssignmentsNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("CondAssignmentsNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(CondAssignNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("CondAssignNode"));
        node.children[0].accept(this);
    }

    void visit(ForeachStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ForeachStmtNode"));
        foreach (child; node.children[1..$])
        {
            child.accept(this);
        }
    }

    void visit(ForeachArgsNode node) {}

    void visit(MatchStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("MatchStmtNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(MatchWhenNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("MatchWhenNode"));
        foreach (child; node.children[1..$])
        {
            child.accept(this);
        }
    }

    void visit(PatternNode node) {}
    void visit(DestructVariantPatternNode node) {}
    void visit(StructPatternNode node) {}
    void visit(BoolPatternNode node) {}
    void visit(StringPatternNode node) {}
    void visit(CharPatternNode node) {}
    void visit(IntPatternNode node) {}
    void visit(FloatPatternNode node) {}
    void visit(TuplePatternNode node) {}
    void visit(ArrayEmptyPatternNode node) {}
    void visit(ArrayPatternNode node) {}
    void visit(ArrayTailPatternNode node) {}
    void visit(WildcardPatternNode node) {}
    void visit(VarOrBareVariantPatternNode node) {}

    // Note that we must cater to the whims of updating
    // this.stackVarAllocSize[curFuncName] with the stack sizes of each variable
    // declared in this expression
    void visit(IsExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("IsExprNode"));
        node.children[0].accept(this);
    }

    void visit(VariantIsMatchNode node) {}
    void visit(IdOrWildcardNode node) {}

    // Note that in the syntax BoolExpr <-= BoolExpr, the left expression must
    // yield a chan-type that contains the same type as the type of the right
    // expression
    void visit(ChanWriteNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ChanWriteNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(ChanReadNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ChanReadNode"));
        node.children[0].accept(this);
    }

    void visit(SpawnStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("SpawnStmtNode"));
        // TODO need to update for allowing calling of templated functions

        node.children[1].accept(this);
    }

    void visit(ForStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ForStmtNode"));
        assert(false, "Unimplemented");
    }

    void visit(ForInitNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ForInitNode"));
        assert(false, "Unimplemented");
    }

    void visit(ForConditionalNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ForConditionalNode"));
        assert(false, "Unimplemented");
    }

    void visit(ForPostExpressionNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ForPostExpressionNode"));
        assert(false, "Unimplemented");
    }

    void visit(LambdaNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("LambdaNode"));
        assert(false, "Unimplemented");
    }

    void visit(LambdaArgsNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("LambdaArgsNode"));
        assert(false, "Unimplemented");
    }

    void visit(StructFunctionNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("StructFunctionNode"));
        assert(false, "Unimplemented");
    }

    void visit(InBlockNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("InBlockNode"));
        assert(false, "Unimplemented");
    }

    void visit(OutBlockNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("OutBlockNode"));
        assert(false, "Unimplemented");
    }

    void visit(ReturnModBlockNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ReturnModBlockNode"));
        assert(false, "Unimplemented");
    }

    void visit(BodyBlockNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("BodyBlockNode"));
        assert(false, "Unimplemented");
    }

    void visit(TypeIdNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("TypeIdNode"));
        auto child = node.children[0];
        // If it's a usertype, there's a chance we need to do a template
        // replacement
        if (cast(UserTypeNode)child)
        {
            // Get id
            (cast(ASTNonTerminal)child).children[0].accept(this);
            auto typename = id;
            if (inFuncParams(typename))
            {
                auto replaceType = getTypeFromPair(typename);
                node.children[0] = genTypeTree(typename, replaceType);
            }
            else
            {
                child.accept(this);
            }
        }
        else
        {
            child.accept(this);
        }
    }

    void visit(BasicTypeNode node) {}

    void visit(ArrayTypeNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ArrayTypeNode"));
        if (node.children.length > 1)
        {
            node.children[1].accept(this);
        }
        else
        {
            node.children[0].accept(this);
        }
    }

    void visit(SetTypeNode node) {}

    void visit(HashTypeNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("HashTypeNode"));
        node.children[1].accept(this);
    }

    void visit(TypeTupleNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("TypeTupleNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(ChanTypeNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ChanTypeNode"));
        node.children[0].accept(this);
    }

    void visit(UserTypeNode node) {}

    void visit(TemplateInstantiationNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("TemplateInstantiationNode"));
        node.children[0].accept(this);
    }

    void visit(TemplateParamNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("TemplateParamNode"));
        node.children[0].accept(this);
    }

    void visit(TemplateParamListNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("TemplateParamListNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(TemplateAliasNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("TemplateAliasNode"));
        node.children[0].accept(this);
    }

    void visit(NumberNode node) {}
    void visit(IntNumNode node) {}
    void visit(FloatNumNode node) {}
    void visit(CharLitNode node) {}
    void visit(StringLitNode node) {}
    void visit(BooleanLiteralNode node) {}
    void visit(SliceLengthSentinelNode node) {}
    void visit(YieldStmtNode node) {}
    void visit(IdTupleNode node) {}
    void visit(FuncRefTypeNode node) {}
    void visit(FuncRefRetTypeNode node) {}
    void visit(InterfaceDefNode node) {}
    void visit(InterfaceBodyNode node) {}
    void visit(InterfaceEntryNode node) {}
    void visit(ASTTerminal node) {}
    void visit(AssignExistingOpNode node) {}
    void visit(StorageClassNode node) {}
    void visit(ConstClassNode node) {}
    void visit(ExternStructDeclNode node) {}
    void visit(ExternFuncDeclNode node) {}
    void visit(StructDefNode node) {}
    void visit(StructBodyNode node) {}
    void visit(StructEntryNode node) {}
    void visit(VariantDefNode node) {}
    void visit(VariantBodyNode node) {}
    void visit(VariantEntryNode node) {}
    void visit(CompOpNode node) {}
    void visit(SumOpNode node) {}
    void visit(SpNode node) {}
    void visit(ProgramNode node) {}
}
