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

debug (FUNCTION_TYPECHECK_TRACE)
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

class FunctionSigBuilder : Visitor
{
    private RecordBuilder records;
    private string id;
    private string[] idTuple;
    private string funcName;
    private VarTypePair*[] funcArgs;
    private Type* returnType;
    private VarTypePair*[] decls;
    FuncSig* funcSig;

    mixin TypeVisitors;

    this (ASTNode node, RecordBuilder records)
    {
        this.records = records;
        builderStack.length++;
        node.accept(this);
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

    void visit(ExternFuncDeclNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ExternFuncDeclNode"));
        // Visit IdentifierNode, populate 'id'
        node.children[0].accept(this);
        funcName = id;
        // Visit FuncDefArgListNode
        node.children[1].accept(this);
        // Visit FuncReturnTypeNode
        node.children[2].accept(this);
        funcSig = new FuncSig();
        funcSig.funcName = funcName;
        funcSig.funcArgs = funcArgs;
        funcSig.returnType = returnType;
        funcName = "";
        funcArgs = [];
        returnType = null;
    }

    void visit(FuncDefNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncDefNode"));
        // Visit FuncSignatureNode
        node.children[0].accept(this);
        funcSig = new FuncSig();
        funcSig.funcName = funcName;
        funcSig.templateParams = templateParams;
        funcSig.funcDefNode = node;
        if (templateParams.length == 0)
        {
            funcSig.funcArgs = funcArgs;
            funcSig.returnType = returnType;
        }
        funcName = "";
        funcArgs = [];
        returnType = null;
        templateParams = [];
    }

    void visit(FuncSignatureNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncSignatureNode"));
        // Visit IdentifierNode, populate 'id'
        node.children[0].accept(this);
        funcName = id;
        // Visit TemplateTypeParamsNode
        node.children[1].accept(this);
        if (templateParams.length > 0)
        {
            return;
        }
        // Visit FuncDefArgListNode
        node.children[2].accept(this);
        // Visit FuncReturnTypeNode
        node.children[3].accept(this);
    }

    void visit(IdentifierNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("IdentifierNode"));
        id = (cast(ASTTerminal)node.children[0]).token;
    }

    void visit(IdTupleNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("IdTupleNode"));
        idTuple = [];
        foreach (child; node.children)
        {
            child.accept(this);
            idTuple ~= id;
        }
    }

    void visit(FuncDefArgListNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncDefArgListNode"));
        foreach (child; node.children)
        {
            // Visit FuncSigArgNode
            child.accept(this);
        }
    }

    void visit(FuncSigArgNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncSigArgNode"));
        // Visit IdentifierNode, populate 'id'
        node.children[0].accept(this);
        string argName = id;
        // Visit TypeIdNode. Note going out of order here
        node.children[$-1].accept(this);
        auto argType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        argType.constType = false;
        if (node.children.length > 2)
        {
            // Visit StorageClassNode
            foreach (storageClass; node.children[1..$-1])
            {
                if (typeid(storageClass) == typeid(ConstClassNode))
                {
                    argType.constType = true;
                }
            }
        }
        auto pair = new VarTypePair();
        pair.varName = argName;
        pair.type = argType;
        funcArgs ~= pair;
    }

    void visit(FuncReturnTypeNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncReturnTypeNode"));
        if (node.children.length > 0)
        {
            node.children[0].accept(this);
            returnType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
        }
        else
        {
            auto voidType = new Type;
            voidType.tag = TypeEnum.VOID;
            returnType = voidType;
        }
    }

    void visit(VariableTypePairNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("VariableTypePairNode"));
        // Visit IdentifierNode, populate 'id'
        node.children[0].accept(this);
        auto varName = id;
        // Visit TypeIdNode
        node.children[1].accept(this);
        auto varType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        auto pair = new VarTypePair();
        pair.varName = varName;
        pair.type = varType;
        decls ~= pair;
    }

    void visit(VariableTypePairTupleNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("VariableTypePairTupleNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(UserTypeNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("UserTypeNode"));
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
        builderStack[$-1] ~= instantiateAggregate(records, aggregate);
    }

    void visit(IsExprNode node) {}
    void visit(VariantIsMatchNode node) {}
    void visit(IdOrWildcardNode node) {}
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
    void visit(ParenExprNode node) {}
    void visit(NumberNode node) {}
    void visit(IntNumNode node) {}
    void visit(FloatNumNode node) {}
    void visit(CharLitNode node) {}
    void visit(StringLitNode node) {}
    void visit(BooleanLiteralNode node) {}
    void visit(ArrayLiteralNode node) {}
    void visit(DeclarationNode node) {}
    void visit(DeclAssignmentNode node) {}
    void visit(AssignExistingNode node) {}
    void visit(DeclTypeInferNode node) {}
    void visit(AssignmentNode node) {}
    void visit(ValueTupleNode node) {}
    void visit(LorRValueNode node) {}
    void visit(LorRTrailerNode node) {}
    void visit(SlicingNode node) {}
    void visit(SingleIndexNode node) {}
    void visit(IndexRangeNode node) {}
    void visit(StartToIndexRangeNode node) {}
    void visit(IndexToEndRangeNode node) {}
    void visit(IndexToIndexRangeNode node) {}

    void visit(LambdaNode node) {}
    void visit(LambdaArgsNode node) {}
    void visit(StructFunctionNode node) {}
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
    void visit(AssignExistingOpNode node) {}
    void visit(CondAssignmentsNode node) {}
    void visit(CondAssignNode node) {}
    void visit(SliceLengthSentinelNode node) {}
    void visit(ChanReadNode node) {}
    void visit(TrailerNode node) {}
    void visit(DynArrAccessNode node) {}
    void visit(TemplateInstanceMaybeTrailerNode node) {}
    void visit(FuncCallTrailerNode node) {}
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
    void visit(ArrayEmptyPatternNode node) {}
    void visit(ArrayPatternNode node) {}
    void visit(ArrayTailPatternNode node) {}
    void visit(WildcardPatternNode node) {}
    void visit(VarOrBareVariantPatternNode node) {}

    void visit(StructConstructorNode node) {}
    void visit(StructMemberConstructorNode node) {}
    void visit(ASTTerminal node) {}
    void visit(ExternStructDeclNode node) {}
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
