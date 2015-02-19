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

class TemplateInstantiator : Visitor
{
    private string id;
    private uint index;
    private string funcName;
    private Type*[] types;
    private string[] templateParams;
    private string[] funcParams;

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

    auto instantiateFunction(FuncDefNode node, Type*[] types)
    {
        node = node.copy;
        this.types = types;
        node.accept(this);
    }

    void visit(IdentifierNode node)
    {
        id = (cast(ASTTerminal)node.children[0]).token;
        index = (cast(ASTTerminal)node.children[0]).index;
    }

    void visit(FuncDefNode node)
    {
        foreach (child; node.children)
        {
            node.accept(this);
        }
    }

    void visit(FuncSignatureNode node)
    {
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

    void visit(FuncDefArgListNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(FuncSigArgNode node)
    {

    }

    void visit(FuncReturnTypeNode node)
    {

    }

    void visit(FuncBodyBlocksNode node)
    {}

    void visit(BareBlockNode node)
    {}

    void visit(StatementNode node)
    {}

    void visit(ReturnStmtNode node)
    {}

    void visit(BoolExprNode node)
    {}

    void visit(OrTestNode node)
    {}

    void visit(AndTestNode node)
    {}

    void visit(NotTestNode node)
    {}

    void visit(ComparisonNode node)
    {}

    void visit(ExprNode node)
    {}

    void visit(OrExprNode node)
    {}

    void visit(XorExprNode node)
    {}

    void visit(AndExprNode node)
    {}

    void visit(ShiftExprNode node)
    {}

    void visit(SumExprNode node)
    {}

    void visit(ProductExprNode node)
    {}

    void visit(ValueNode node)
    {}

    void visit(ParenExprNode node)
    {}

    void visit(NumberNode node)
    {}

    void visit(IntNumNode node)
    {}

    void visit(FloatNumNode node)
    {}

    void visit(CharLitNode node)
    {}

    void visit(StringLitNode node)
    {}

    void visit(BooleanLiteralNode node)
    {}

    void visit(StructConstructorNode node)
    {}

    void visit(StructMemberConstructorNode node) {}

    void visit(ArrayLiteralNode node)
    {}

    void visit(VariableTypePairNode node)
    {}

    void visit(VariableTypePairTupleNode node)
    {}

    void visit(DeclarationNode node)
    {}

    void visit(DeclAssignmentNode node)
    {}

    void visit(AssignExistingNode node)
    {}

    void visit(DeclTypeInferNode node)
    {}

    void visit(AssignmentNode node)
    {}

    void visit(ValueTupleNode node)
    {}

    void visit(LorRValueNode node)
    {}

    void visit(LorRTrailerNode node)
    {}

    void visit(SlicingNode node)
    {}

    void visit(SingleIndexNode node)
    {}

    void visit(IndexRangeNode node)
    {}

    void visit(StartToIndexRangeNode node)
    {}

    void visit(IndexToEndRangeNode node)
    {}

    void visit(IndexToIndexRangeNode node)
    {}

    void visit(TrailerNode node)
    {}

    void visit(DynArrAccessNode node)
    {}

    void visit(TemplateInstanceMaybeTrailerNode node)
    {}

    void visit(SliceLengthSentinelNode node)
    {}

    void visit(UserTypeNode node)
    {}

    void visit(FuncCallTrailerNode node)
    {}

    void visit(FuncCallArgListNode node)
    {}

    void visit(FuncCallNode node)
    {}

    void visit(DotAccessNode node)
    {}

    void visit(IfStmtNode node)
    {}

    void visit(ElseIfsNode node)
    {}

    void visit(ElseIfStmtNode node)
    {}

    void visit(ElseStmtNode node)
    {}

    void visit(WhileStmtNode node)
    {}

    void visit(CondAssignmentsNode node)
    {}

    void visit(CondAssignNode node)
    {}

    void visit(ForeachStmtNode node)
    {}

    void visit(ForeachArgsNode node)
    {}

    void visit(MatchStmtNode node)
    {}

    void visit(MatchWhenNode node)
    {}

    void visit(PatternNode node)
    {}

    void visit(DestructVariantPatternNode node)
    {}

    void visit(StructPatternNode node)
    {}

    void visit(BoolPatternNode node)
    {}

    void visit(StringPatternNode node)
    {}

    void visit(CharPatternNode node)
    {}

    void visit(IntPatternNode node)
    {}

    void visit(FloatPatternNode node)
    {}

    void visit(TuplePatternNode node)
    {}

    void visit(ArrayEmptyPatternNode node)
    {}

    void visit(ArrayPatternNode node)
    {}

    void visit(ArrayTailPatternNode node)
    {}

    void visit(WildcardPatternNode node)
    {}

    void visit(VarOrBareVariantPatternNode node)
    {}

    // Note that we must cater to the whims of updating
    // this.stackVarAllocSize[curFuncName] with the stack sizes of each variable
    // declared in this expression
    void visit(IsExprNode node)
    {}

    void visit(VariantIsMatchNode node) {}
    void visit(IdOrWildcardNode node) {}

    // Note that in the syntax BoolExpr <-= BoolExpr, the left expression must
    // yield a chan-type that contains the same type as the type of the right
    // expression
    void visit(ChanWriteNode node)
    {}

    void visit(ChanReadNode node)
    {}

    void visit(SpawnStmtNode node)
    {}

    void visit(YieldStmtNode node)
    {}

    void visit(IdTupleNode node)
    {}

    void visit(ForStmtNode node) {}
    void visit(ForInitNode node) {}
    void visit(ForConditionalNode node) {}
    void visit(ForPostExpressionNode node) {}
    void visit(LambdaNode node) {}
    void visit(LambdaArgsNode node) {}
    void visit(StructFunctionNode node) {}
    void visit(InBlockNode node) {}
    void visit(OutBlockNode node) {}
    void visit(ReturnModBlockNode node) {}
    void visit(BodyBlockNode node) {}
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

    class ASTTerminal : ASTNode
    {
        const string token;
        const uint index;
        this (string token, uint index) {
            this.token = token;
            this.index = index;
        }
        override void accept(Visitor v) {
            v.visit(this);
        }
    }
    class BasicTypeNode : ASTNonTerminal
    {
        this () {
            this.name = "BASICTYPE";
        }
        override void accept(Visitor v) {
            v.visit(this);
        }
        override Tag getTag() {
            return Tag.BASICTYPE;
        }
    }

    void visit(TypeIdNode node)
    {
        auto child = node.children[0];
        // If it's a usertype, there's a chance we need to do a template
        // replacement
        if (cast(UserTypeNode)child)
        {
            // Get id
            (cast(ASTNonTerminal)child).children[0].accept(this);
            auto typename = id;
            if (typename.inFuncParams)
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
        auto array = new ArrayType();
        if (node.children.length > 1)
        {
            node.children[0].accept(this);
            auto allocType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!isIntegral(allocType))
            {
                throw new Exception("Can only use integral value to prealloc");
            }
            node.children[1].accept(this);
        }
        else
        {
            node.children[0].accept(this);
        }
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

    void visit(TypeTupleNode node)
    {
        auto tuple = new TupleType();
        foreach (child; node.children)
        {
            child.accept(this);
            tuple.types ~= builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
        }
        auto type = new Type();
        type.tag = TypeEnum.TUPLE;
        type.tuple = tuple;
        builderStack[$-1] ~= type;
    }

    void visit(ChanTypeNode node)
    {
        auto chan = new ChanType();
        node.children[0].accept(this);
        auto chanType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        chan.chanType = chanType.copy;
        auto wrap = new Type();
        wrap.chan = chan;
        wrap.tag = TypeEnum.CHAN;
        builderStack[$-1] ~= wrap;
    }

    void visit(FuncRefTypeNode node)
    {
        auto funcRefType = new FuncPtrType();
        Type*[] funcArgs;
        foreach (child; node.children[0..$-1])
        {
            child.accept(this);
            funcArgs ~= builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
        }
        funcRefType.funcArgs = funcArgs;
        auto retTypeNode = cast(FuncRefRetTypeNode)node.children[$-1];
        if (retTypeNode.children.length == 0)
        {
            auto voidRetType = new Type();
            voidRetType.tag = TypeEnum.VOID;
            funcRefType.returnType = voidRetType;
        }
        else
        {
            retTypeNode.children[0].accept(this);
            funcRefType.returnType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
        }
        auto wrap = new Type();
        wrap.tag = TypeEnum.FUNCPTR;
        wrap.funcPtr = funcRefType;
        builderStack[$-1] ~= wrap;
    }

    void visit(FuncRefRetTypeNode node) {}

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
