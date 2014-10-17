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

struct FuncBreakout
{
    string funcName;
    TemplateTypeParamsNode templateParams;
    FuncDefArgListNode argList;
    InBlockNode inBlock;
    OutBlockNode outBlock;
    ReturnModBlockNode returnModBlock;
    BodyBlockNode bodyBlock;
    BareBlockNode bareBlock;
}

// The 'header' for a function type. Note that a function can be any of the
// three of being a closure, a struct member function, or neither. A function
// cannot both be a closure and a struct member function, so there will only
// ever be, at most, a single 'implicit' leading argument, whether it be
// an environment-pointer or a 'this' pointer
struct FuncSig
{
    // The actual name of the function; that which can be called
    string name;
    // A possibly zero-length list of variables that are closed over, indicating
    // this is a closure function. If the length is zero, the number of
    // arguments to the actual implementation of the function is the number
    // of arguments in 'funcArgs', otherwise there is an additional
    // environment-pointer argument
    string[] closureVars;
    // A possibly-empty string indicating the struct that this function is a
    // member of. If this string is empty, then the number of arguments to the
    // actual implementation of this function is the number of arguments in
    // 'funcArgs', otherwise there is an additional 'this' pointer
    string memberOf;
    // The types of the arguments to the function, in the order they appeared
    // in the original argument list
    Type*[] funcArgs;
    // The return type can either be a bare type, or a type tuple. This
    // representation may be changed later, to a more concrete tuple type within
    // 'Type'
    Type*[] returnType;
}

class FunctionBuilder : Visitor
{
    string id;

    this (ProgramNode node)
    {
        writeln("FunctionBuilder: this()");
        auto funcs = collectTopLevelFuncs(node);
        auto printVisitor = new PrintVisitor();
        printVisitor.visit(cast(ProgramNode)node);
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

    private auto collectTopLevelFuncs(ASTNode node)
    {
        auto funcDefs = (cast(ASTNonTerminal)node)
            .children.filter!(a => typeid(a) == typeid(FuncDefNode))
            .map!(a => cast(FuncDefNode)a);
        auto funcSigs =
            funcDefs.map!(a => cast(FuncSignatureNode)(a.children[0]));
        auto funcBodies =
            funcDefs.map!(a => cast(FuncBodyBlocksNode)(a.children[1]));
        FuncBreakout[] breakouts;
        foreach (sig, bodies; lockstep(funcSigs, funcBodies))
        {
            auto idNode = cast(ASTNonTerminal)sig.children[0];
            auto funcName = (cast(ASTTerminal)idNode.children[0]).token;
            auto templateParams = cast(TemplateTypeParamsNode)(sig.children[1]);
            auto argList = cast(FuncDefArgListNode)(sig.children[2]);
            BareBlockNode bareBlock = null;
            InBlockNode inBlock = null;
            OutBlockNode outBlock = null;
            ReturnModBlockNode returnModBlock = null;
            BodyBlockNode bodyBlock = null;
            foreach (block; bodies.children)
            {
                if (auto b = cast(BareBlockNode)block)
                {
                    bareBlock = b;
                }
                else if (auto b = cast(InBlockNode)block)
                {
                    inBlock = b;
                }
                else if (auto b = cast(OutBlockNode)block)
                {
                    outBlock = b;
                }
                else if (auto b = cast(ReturnModBlockNode)block)
                {
                    returnModBlock = b;
                }
                else if (auto b = cast(BodyBlockNode)block)
                {
                    bodyBlock = b;
                }
            }
            FuncBreakout breakout;
            breakout.funcName = funcName;
            breakout.templateParams = templateParams;
            breakout.argList = argList;
            breakout.inBlock = inBlock;
            breakout.outBlock = outBlock;
            breakout.returnModBlock = returnModBlock;
            breakout.bodyBlock = bodyBlock;
            breakout.bareBlock = bareBlock;
            breakouts ~= breakout;
        }
        auto names = breakouts.map!(a => a.funcName).array;
        if (names.length != names.uniq.array.length)
        {
            writeln("Multiple definitions:");
            writeln("  ", collectMultiples(names));
        }
        writeln(names);
        return breakouts;
    }

    void visit(StructDefNode node) {}
    void visit(StructBodyNode node) {}
    void visit(StructEntryNode node) {}
    void visit(VariableTypePairNode node) {}
    void visit(VariantDefNode node) {}
    void visit(VariantBodyNode node) {}
    void visit(VariantEntryNode node) {}
    void visit(VariantVarDeclListNode node) {}
    void visit(TypeIdNode node) {}
    void visit(BasicTypeNode node) {}
    void visit(ArrayTypeNode node) {}
    void visit(SetTypeNode node) {}
    void visit(HashTypeNode node) {}
    void visit(UserTypeNode node) {}
    void visit(IdentifierNode node) {}
    void visit(TemplateTypeParamsNode node) {}
    void visit(TemplateTypeParamListNode node) {}
    void visit(TemplateInstantiationNode node) {}
    void visit(TemplateParamNode node) {}
    void visit(TemplateParamListNode node) {}
    void visit(TemplateAliasNode node) {}
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
