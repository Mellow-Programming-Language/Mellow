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
import Record;

// CLosures and struct member functions can be implemented in exactly the same
// way. The 'this' pointer and the environment pointer for closures are
// identical, as long as the pointer points to a block of memory where each
// variable is allocated. That is, a struct reference pointer is simply a
// pointer to memory where each member is allocated sequentially. If the
// environment pointer follows the same pattern, then the implementation for
// each is the same, and perhaps building the datastructures for handling them
// in the compiler can be the same as well

struct VarTypePair
{
    string varName;
    Type* type;
    bool closedOver;

    auto format()
    {
        return varName ~ ": " ~ type.format();
    }
}

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
    VarTypePair*[] closureVars;
    // A possibly-empty string indicating the struct that this function is a
    // member of. If this string is empty, then the number of arguments to the
    // actual implementation of this function is the number of arguments in
    // 'funcArgs', otherwise there is an additional 'this' pointer
    string memberOf;
    // The types of the arguments to the function, in the order they appeared
    // in the original argument list
    VarTypePair*[] funcArgs;
    // The return type. Since it's a bare type, it can possibly be a tuple of
    // types
    Type* returnType;
}

struct SymbolScope
{
    VarTypePair*[string] decls;

    auto format()
    {
        return decls.values.map!(a => a.format).join(", ");
    }
}

auto format(SymbolScope[] symbols)
{
    string str = "";
    string indent = "";
    foreach (symbolScope; symbols)
    {
        str ~= indent ~ symbolScope.format ~ "\n";
        indent ~= "  ";
    }
    return str;
}

struct FunctionScope
{
    SymbolScope[] syms;
}

struct ScopeLookupResult
{
    ulong funcIndex;
    ulong symIndex;
    bool nonlocal;

    this (ulong funcIndex, ulong symIndex, bool nonlocal)
    {
        this.funcIndex = funcIndex;
        this.symIndex = symIndex;
        this.nonlocal = nonlocal;
    }
}

auto scopeLookup(FunctionScope[] funcScopes, string id)
{
    bool nonlocal = false;
    foreach_reverse (i, funcScope; funcScopes)
    {
        foreach_reverse (j, symScope; funcScope.syms)
        {
            if (id in symScope.decls)
            {
                if (i < funcScopes.length - 1)
                {
                    nonlocal = true;
                }
                return new ScopeLookupResult(i, j, nonlocal);
            }
        }
    }
    return null;
}

void updateIfClosedOver(FunctionScope[] funcScopes, string id)
{
    auto lookup = funcScopes.scopeLookup(id);
    if (lookup.nonlocal)
    {
        funcScopes[lookup.funcIndex].syms[lookup.symIndex]
                                    .decls[id]
                                    .closedOver = true;
    }
}

Type* instantiateAggregate(RecordBuilder records, AggregateType* aggregate)
{
    if (aggregate.typeName in records.structDefs)
    {
        auto structDef = records.structDefs[aggregate.typeName].copy;
        Type*[string] mappings;
        if (aggregate.templateInstantiations.length
            != structDef.templateParams.length)
        {
            throw new Exception("Template instantiation count mismatch.");
        }
        else
        {
            foreach (var, type; lockstep(structDef.templateParams,
                                    aggregate.templateInstantiations))
            {
                mappings[var] = type.copy;
            }
        }
        structDef.instantiate(mappings);
        auto type = new Type();
        type.tag = TypeEnum.AGGREGATE;
        type.structDef = structDef;
        return type;
    }
    else if (aggregate.typeName in records.variantDefs)
    {
        auto variantDef = records.variantDefs[aggregate.typeName].copy;
        Type*[string] mappings;
        if (aggregate.templateInstantiations.length
            != variantDef.templateParams.length)
        {
            throw new Exception("Template instantiation count mismatch.");
        }
        else
        {
            foreach (var, type; lockstep(variantDef.templateParams,
                                    aggregate.templateInstantiations))
            {
                mappings[var] = type.copy;
            }
        }
        variantDef.instantiate(mappings);
        auto type = new Type();
        type.tag = TypeEnum.AGGREGATE;
        type.variantDef = variantDef;
        return type;
    }
    else
    {
        throw new Exception("Instantiation of non-existent type.");
    }
}

class FunctionBuilder : Visitor
{
    RecordBuilder records;
    string id;
    string[] idTuple;
    string funcName;
    string[] templateParams;
    VarTypePair*[] funcArgs;
    FuncSig[] toplevelFuncs;
    Type* returnType;
    // The higher the index, the deeper the scope
    FunctionScope[] funcScopes;
    VarTypePair*[] decls;
    Type* lvalue;

    mixin TypeVisitors;

    this (ProgramNode node, RecordBuilder records)
    {
        this.records = records;
        builderStack.length++;
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
        funcScopes.length++;
        funcScopes[$-1].syms.length++;
        // Visit FuncSignatureNode
        node.children[0].accept(this);
        FuncSig funcSig;
        funcSig.funcName = funcName;
        funcSig.funcArgs = funcArgs;
        funcSig.returnType = returnType;
        // Visit FuncBodyBlocksNode
        node.children[1].accept(this);

        // Do final put-together here

        funcScopes.length--;
    }

    void visit(FuncSignatureNode node)
    {
        // Visit IdentifierNode, populate 'id'
        node.children[0].accept(this);
        funcName = id;
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
        builderStack[$-1] = builderStack[$-1][0..$-1];
        argType.refType = false;
        argType.constType = false;
        if (node.children.length > 2)
        {
            // Visit StorageClassNode
            foreach (storageClass; node.children[1..$-1])
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
        auto pair = new VarTypePair();
        pair.varName = argName;
        pair.type = argType;
        funcArgs ~= pair;
        funcScopes[$-1].syms[$-1].decls[argName] = pair;
        writeln(format(funcScopes[$-1].syms));
    }

    void visit(FuncReturnTypeNode node)
    {
        if (node.children.length > 0)
        {
            node.children[0].accept(this);
            returnType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
        }
    }

    void visit(FuncBodyBlocksNode node)
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

    void visit(StatementNode node)
    {
        node.children[0].accept(this);
    }

    void visit(ReturnStmtNode node)
    {
        if (node.children.length > 0)
        {
            node.children[0].accept(this);
        }
    }

    void visit(BoolExprNode node)
    {
        node.children[0].accept(this);
    }

    void visit(OrTestNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(AndTestNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(NotTestNode node)
    {
        node.children[0].accept(this);
    }

    void visit(ComparisonNode node)
    {
        foreach (child; node.children.stride(2))
        {
            child.accept(this);
        }
    }

    void visit(ExprNode node)
    {
        node.children[0].accept(this);
    }

    void visit(OrExprNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(XorExprNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(AndExprNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(ShiftExprNode node)
    {
        foreach (child; node.children.stride(2))
        {
            child.accept(this);
        }
    }

    void visit(SumExprNode node)
    {
        foreach (child; node.children.stride(2))
        {
            child.accept(this);
        }
    }

    void visit(ProductExprNode node)
    {
        foreach (child; node.children.stride(2))
        {
            child.accept(this);
        }
    }

    void visit(ValueNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(VariableTypePairNode node)
    {
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
        funcScopes[$-1].syms[$-1].decls[varName] = pair;
        decls ~= pair;
    }

    void visit(VariableTypePairTupleNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(DeclarationNode node)
    {
        node.children[0].accept(this);
        decls = [];
    }

    void visit(DeclAssignmentNode node)
    {
        node.children[0].accept(this);
        node.children[1].accept(this);
        auto varType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (varType.tag == TypeEnum.TUPLE)
        {
            auto tupleTypes = varType.tuple.types;
            if (tupleTypes.length != decls.length)
            {
                throw new Exception("Tuple member count mismatch.");
            }
            foreach (decl, varType; lockstep(decls, tupleTypes))
            {
                if (decl.type != varType)
                {
                    throw new Exception("Type mismatch in tuple unpack.");
                }
            }
        }
        else
        {
            if (decls[$-1].type != varType)
            {
                throw new Exception("Type mismatch in decl assignment.");
            }
        }
    }

    void visit(AssignExistingNode node)
    {
        lvalue = null;
        node.children[0].accept(this);
        node.children[2].accept(this);
    }

    void visit(DeclTypeInferNode node)
    {
        node.children[0].accept(this);
        if (typeid(node.children[0]) == typeid(IdTupleNode))
        {
            string[] varNames = idTuple;
            node.children[1].accept(this);
            auto varTuple = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (varTuple.tag != TypeEnum.TUPLE)
            {
                throw new Exception("Non-Tuple type!");
            }
            auto tupleTypes = varTuple.tuple.types;
            if (tupleTypes.length != varNames.length)
            {
                throw new Exception("Tuple member count mismatch.");
            }
            foreach (varName, varType; lockstep(varNames, tupleTypes))
            {
                auto pair = new VarTypePair();
                pair.varName = varName;
                pair.type = varType;
                funcScopes[$-1].syms[$-1].decls[varName] = pair;
            }
        }
        else if (typeid(node.children[0]) == typeid(IdentifierNode))
        {
            string varName = id;
            node.children[1].accept(this);
            auto varType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            auto pair = new VarTypePair();
            pair.varName = varName;
            pair.type = varType;
            funcScopes[$-1].syms[$-1].decls[varName] = pair;
        }
    }

    void visit(AssignmentNode node)
    {
        node.children[0].accept(this);
    }

    void visit(ValueTupleNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(LorRValueNode node)
    {
        node.children[0].accept(this);
        string varName = id;
        if (lvalue is null)
        {
            funcScopes.updateIfClosedOver(varName);
            auto lookup = funcScopes.scopeLookup(varName);
            auto varType = funcScopes[lookup.funcIndex].syms[lookup.symIndex]
                                                       .decls[varName]
                                                       .type;
        }
        // This means the varName is a member of whatever the current lvalue
        // type is
        else
        {
            switch (lvalue.tag)
            {
            case TypeEnum.STRUCT:
                //foreach (memberName; lvalue.structDef)
                break;
            default:
                throw new Exception("No member of non-struct type.");
            }
        }
        if (node.children.length > 1)
        {
            node.children[1].accept(this);
        }
    }

    void visit(LorRTrailerNode node) {}
    void visit(LorRMemberAccessNode node) {}
    void visit(ParenExprNode node) {}
    void visit(ArrayLiteralNode node) {}
    void visit(LambdaNode node) {}
    void visit(LambdaArgsNode node) {}
    void visit(StructFunctionNode node) {}
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
    void visit(AssignExistingOpNode node) {}
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
    void visit(IdTupleNode node) {}

    void visit(ASTTerminal node) {}
    void visit(StructDefNode node) {}
    void visit(StructBodyNode node) {}
    void visit(StructEntryNode node) {}
    void visit(VariantDefNode node) {}
    void visit(VariantBodyNode node) {}
    void visit(VariantEntryNode node) {}
    void visit(VariantVarDeclListNode node) {}
    void visit(NumberNode node) {}
    void visit(IntNumNode node) {}
    void visit(FloatNumNode node) {}
    void visit(CharLitNode node) {}
    void visit(StringLitNode node) {}
    void visit(ProgramNode node) {}
    void visit(CharRangeNode node) {}
    void visit(IntRangeNode node) {}
    void visit(BooleanLiteralNode node) {}
    void visit(CompOpNode node) {}
    void visit(SumOpNode node) {}
    void visit(SpNode node) {}
}
