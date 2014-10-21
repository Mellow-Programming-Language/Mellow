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

// CLosures and struct member functions can be implemented in exactly the same
// way. The 'this' pointer and the environment pointer for closures are
// identical, as long as the pointer points to a block of memory where each
// variable is allocated. That is, a struct reference pointer is simply a
// pointer to memory where each member is allocated sequentially. If the
// environment pointer follows the same pattern, then the implementation for
// each is the same, and perhaps building the datastructures for handling them
// in the compiler can be the same as well

// The 'header' for a function type. Note that a function can be any of the
// three of being a closure, a struct member function, or neither. A function
// cannot both be a closure and a struct member function, so there will only
// ever be, at most, a single 'implicit' leading argument, whether it be
// an environment-pointer or a 'this' pointer
struct FuncSig
{
    // The actual name of the function; that which can be called
    string funcName;
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
    // The return type. Since it's a bare type, it can possibly be a tuple of
    // types
    Type* returnType;
}

struct SymbolScope
{
    Type*[string] decls;
}

class FunctionBuilder : Visitor
{
    string id;
    FuncSig[] toplevelFuncs;
    // First index is the function being catered to, second index is the
    // types that are part of that function's arguments
    Type*[][] funcArgs;
    string[] templateParams;
    // The higher the index, the deeper the scope
    SymbolScope[] symbols;

    mixin TypeVisitors;

    this (ProgramNode node)
    {
        builderStack.length++;
        symbols.length++;
        // Just do function definitions
        auto funcDefs = node.children
                            .filter!(a => typeid(a) == typeid(FuncDefNode));
        foreach (funcDef; funcDefs)
        {
            funcDef.accept(this);
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

    void visit(FuncDefNode node)
    {
        // Visit FuncSignatureNode
        node.children[0].accept(this);
        // Visit FuncBodyBlocksNode
        node.children[1].accept(this);

        // Do final put-together here
    }

    void visit(FuncSignatureNode node)
    {
        // Visit IdentifierNode, populate 'id'
        node.children[0].accept(this);
        string funcName = id;
        writeln("FuncName: ", id);
        // Visit TemplateTypeParamsNode
        node.children[1].accept(this);
        // Visit FuncDefArgListNode
        node.children[2].accept(this);
        // Visit FuncReturnTypeNode
        node.children[3].accept(this);
    }

    void visit(IdentifierNode node)
    {
        id = (cast(ASTTerminal)node.children[0]).token;
    }

    void visit(FuncDefArgListNode node)
    {
        foreach (child; node.children)
        {
            // Visit FuncSigArgNode
            child.accept(this);
        }
    }

    void visit(FuncSigArgNode node)
    {
        // Visit IdentifierNode, populate 'id'
        node.children[0].accept(this);
        string argName = id;
        // Visit TypeIdNode. Note going out of order here
        node.children[$-1].accept(this);
        auto argType = builderStack[$-1][$-1];
        argType.refType = false;
        argType.constType = false;
        if (node.children.length > 2)
        {
            // Visit StorageClassNode
            foreach (storageClass; node.children[1..$-2])
            {
                if (typeid(storageClass) == typeid(RefClassNode))
                {
                    argType.refType = true;
                }
                else if (typeid(storageClass) == typeid(ConstClassNode))
                {
                    argType.constType = true;
                }
            }
        }
        symbols[$-1].decls[id] = argType;
        writeln(symbols);
    }

    void visit(FuncBodyBlocksNode node)
    {

    }

    void visit(BareBlockNode node) {}

    void visit(StructDefNode node) {}
    void visit(StructBodyNode node) {}
    void visit(StructEntryNode node) {}
    void visit(VariableTypePairNode node) {}
    void visit(VariantDefNode node) {}
    void visit(VariantBodyNode node) {}
    void visit(VariantEntryNode node) {}
    void visit(VariantVarDeclListNode node) {}
    void visit(ProgramNode node) {}
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
