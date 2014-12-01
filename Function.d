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
import utils;
import FunctionSig;

// CLosures and struct member functions can be implemented in exactly the same
// way. The 'this' pointer and the environment pointer for closures are
// identical, as long as the pointer points to a block of memory where each
// variable is allocated. That is, a struct reference pointer is simply a
// pointer to memory where each member is allocated sequentially. If the
// environment pointer follows the same pattern, then the implementation for
// each is the same, and perhaps building the datastructures for handling them
// in the compiler can be the same as well

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
    foreach (symbolScope; symbols[0..$-1])
    {
        str ~= indent ~ symbolScope.format ~ "\n";
        indent ~= "  ";
    }
    if (symbols.length > 0)
    {
        str ~= indent ~ symbols[$-1].format;
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
    bool success;

    this (ulong funcIndex, ulong symIndex, bool nonlocal, bool success)
    {
        this.funcIndex = funcIndex;
        this.symIndex = symIndex;
        this.nonlocal = nonlocal;
        this.success = success;
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
                return new ScopeLookupResult(i, j, nonlocal, true);
            }
        }
    }
    return new ScopeLookupResult(0, 0, false, false);
}

struct FuncSigLookupResult
{
    FuncSig* sig;
    bool success;

    this (bool success = false)
    {
        this.success = success;
    }

    this (FuncSig* sig)
    {
        this.sig = sig;
        this.success = true;
    }
}

auto funcSigLookup(FuncSig*[] sigs, string name)
{
    foreach (sig; sigs)
    {
        if (name == sig.funcName)
        {
            return FuncSigLookupResult(sig);
        }
    }
    return FuncSigLookupResult();
}

void updateIfClosedOver(FunctionScope[] funcScopes, string id)
{
    auto lookup = funcScopes.scopeLookup(id);
    if (lookup.success && lookup.nonlocal)
    {
        funcScopes[lookup.funcIndex].syms[lookup.symIndex]
                                    .decls[id]
                                    .closedOver = true;
    }
}

debug (TYPECHECK)
void dumpDecls(VarTypePair*[] decls)
{
    foreach (decl; decls)
    {
        decl.format.writeln;
    }
}

class FunctionBuilder : Visitor
{
    private RecordBuilder records;
    private string id;
    private FuncSig* funcSig;
    private FuncSig* curFuncCallSig;
    private string[] idTuple;
    private VarTypePair*[] funcArgs;
    private FuncSig*[] toplevelFuncs;
    // The higher the index, the deeper the scope
    private FunctionScope[] funcScopes;
    private VarTypePair*[] decls;
    private Type* lvalue;
    private uint insideSlice;
    private string[] foreachArgs;

    mixin TypeVisitors;

    this (ProgramNode node, RecordBuilder records, FunctionSigBuilder sigs)
    {
        this.records = records;
        this.toplevelFuncs = sigs.toplevelFuncs;
        builderStack.length++;
        // Just do function definitions
        auto funcDefs = node.children
                            .filter!(a => typeid(a) == typeid(FuncDefNode));
        foreach (funcDef; funcDefs)
        {
            funcDef.accept(this);
        }
        insideSlice = 0;
    }

    void visit(FuncDefNode node)
    {
        funcScopes.length++;
        funcScopes[$-1].syms.length++;
        // Visit FuncSignatureNode
        node.children[0].accept(this);
        // Visit FuncBodyBlocksNode
        node.children[1].accept(this);
        funcScopes.length--;
    }

    void visit(FuncSignatureNode node)
    {
        // Visit IdentifierNode, populate 'id'
        node.children[0].accept(this);
        auto funcName = id;
        auto lookup = funcSigLookup(toplevelFuncs, funcName);
        funcSig = lookup.sig;
        foreach (arg; lookup.sig.funcArgs)
        {
            funcScopes[$-1].syms[$-1].decls[arg.varName] = arg;
        }
    }

    void visit(IdentifierNode node)
    {
        id = (cast(ASTTerminal)node.children[0]).token;
    }

    void visit(IdTupleNode node)
    {
        idTuple = [];
        foreach (child; node.children)
        {
            child.accept(this);
            idTuple ~= id;
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
        funcScopes[$-1].syms.length++;
        foreach (child; node.children)
        {
            child.accept(this);
        }
        funcScopes[$-1].syms.length--;
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
            auto returnType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!returnType.cmp(funcSig.returnType))
            {
                throw new Exception("Wrong type for return.");
            }
        }
    }

    void visit(BoolExprNode node)
    {
        node.children[0].accept(this);
    }

    void visit(OrTestNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!resultType.tag != TypeEnum.BOOL
                || !nextType.tag != TypeEnum.BOOL)
            {
                throw new Exception("Non-bool type in LOGIC-OR.");
            }
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(AndTestNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!resultType.tag != TypeEnum.BOOL
                || !nextType.tag != TypeEnum.BOOL)
            {
                throw new Exception("Non-bool type in LOGIC-AND.");
            }
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(NotTestNode node)
    {
        node.children[0].accept(this);
        if (typeid(node.children[0]) == typeid(NotTestNode))
        {
            if (builderStack[$-1][$-1].tag != TypeEnum.BOOL)
            {
                throw new Exception("Cannot negate non-bool type.");
            }
        }
    }

    void visit(ComparisonNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        Type* chainCompare = null;
        if (node.children.length > 1)
        {
            auto op = (cast(ASTTerminal)node.children[1]).token;
            node.children[2].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            final switch (op)
            {
            case "<=":
            case ">=":
            case "<":
            case ">":
                if (!resultType.isNumeric || !nextType.isNumeric)
                {
                    throw new Exception("Cannot compare non-integral types.");
                }
                break;
            case "==":
            case "!=":
                if (resultType.isNumeric && nextType.isNumeric) {}
                else if (resultType.cmp(nextType) &&
                      (resultType.tag == TypeEnum.CHAR
                    || resultType.tag == TypeEnum.BOOL
                    || resultType.tag == TypeEnum.STRING)) {}
                else
                {
                    throw new Exception("Mismatched types for equality cmp.");
                }
                break;
            case "<in>":
                if (resultType.tag != TypeEnum.SET
                    || nextType.tag != TypeEnum.SET
                    || !resultType.set.setType.cmp(nextType.set.setType))
                {
                    throw new Exception("Mismatched types in <in> op.");
                }
                break;
            case "in":
                if (nextType.tag != TypeEnum.SET
                    || !nextType.set.setType.cmp(resultType))
                {
                    throw new Exception("Mismatched types in in op.");
                }
                break;
            }
            auto boolType = new Type();
            boolType.tag = TypeEnum.BOOL;
            resultType = boolType;
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(ExprNode node)
    {
        node.children[0].accept(this);
    }

    void visit(OrExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!resultType.isIntegral || !nextType.isIntegral)
            {
                throw new Exception("Non-integral type in BIT-OR operation.");
            }
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(XorExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!resultType.isIntegral || !nextType.isIntegral)
            {
                throw new Exception("Non-integral type in BIT-XOR operation.");
            }
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(AndExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!resultType.isIntegral || !nextType.isIntegral)
            {
                throw new Exception("Non-integral type in BIT-AND operation.");
            }
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(ShiftExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!resultType.isIntegral || !nextType.isIntegral)
            {
                throw new Exception("Non-integral type in shift operation.");
            }
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(SumExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            auto op = (cast(ASTTerminal)node.children[i-1]).token;
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            final switch (op)
            {
            case "+":
            case "-":
                resultType = promoteNumeric(resultType, nextType);
                break;
            case "<|>":
            case "<&>":
            case "<^>":
            case "<->":
                if (!resultType.cmp(nextType)
                    || resultType.tag != TypeEnum.SET
                    || nextType.tag != TypeEnum.SET)
                {
                    throw new Exception("Type mismatch in set operation.");
                }
                break;
            case "~":
                if (resultType.cmp(nextType))
                {
                    if (resultType.tag == TypeEnum.ARRAY)
                    {
                        // Result type remains the same, we're appending to like
                        // arrays together
                    }
                    else
                    {
                        // Result type is the type of appending two non-array
                        // types together, to create a two-element array
                        auto arrayType = new ArrayType();
                        arrayType.arrayType = resultType;
                        auto type = new Type();
                        type.tag = TypeEnum.ARRAY;
                        type.array = arrayType;
                        resultType = type;
                    }
                }
                // If the types are not the same, then one of them must be the
                // array wrapper of the other type
                else
                {
                    if (resultType.tag == TypeEnum.ARRAY)
                    {
                        if (!resultType.array.arrayType.cmp(nextType))
                        {
                            throw new Exception(
                                "Cannot append base type to unlike array type");
                        }
                    }
                    else if (nextType.tag == TypeEnum.ARRAY)
                    {
                        if (!nextType.array.arrayType.cmp(resultType))
                        {
                            throw new Exception(
                                "Cannot append base type to unlike array type");
                        }
                        resultType = nextType;
                    }
                    else
                    {
                        throw new Exception(
                            "Cannot append two unlike, non-array types.");
                    }
                }
            }
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(ProductExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            auto op = (cast(ASTTerminal)node.children[i-1]).token;
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!resultType.isNumeric || !nextType.isNumeric)
            {
                throw new Exception("Cannot perform " ~ op ~ " on non-arith.");
            }
            if (op == "%" && (resultType.isFloat || nextType.isFloat))
            {
                throw new Exception("% (modulus) undefined for float types.");
            }
            resultType = promoteNumeric(resultType, nextType);
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(ValueNode node)
    {
        if (typeid(node.children[0]) == typeid(IdentifierNode))
        {
            node.children[0].accept(this);
            auto name = id;
            auto varLookup = funcScopes.scopeLookup(name);
            auto funcLookup = funcSigLookup(toplevelFuncs, name);
            if (!varLookup.success && !funcLookup.success)
            {
                throw new Exception("No variable or function[" ~ name ~ "].");
            }
            else if (varLookup.success)
            {
                auto varType = funcScopes[varLookup.funcIndex]
                                    .syms[varLookup.symIndex]
                                    .decls[name]
                                    .type;
                builderStack[$-1] ~= varType;
            }
            else if (funcLookup.success)
            {
                curFuncCallSig = funcLookup.sig;
            }
            if (node.children.length > 1)
            {
                node.children[1].accept(this);
            }
        }
        else
        {
            foreach (child; node.children)
            {
                child.accept(this);
            }
        }
    }

    void visit(ParenExprNode node)
    {
        node.children[0].accept(this);
    }

    void visit(NumberNode node)
    {
        node.children[0].accept(this);
    }

    void visit(IntNumNode node)
    {
        auto valType = new Type();
        valType.tag = TypeEnum.INT;
        builderStack[$-1] ~= valType;
    }

    void visit(FloatNumNode node)
    {
        auto valType = new Type();
        valType.tag = TypeEnum.FLOAT;
        builderStack[$-1] ~= valType;
    }

    void visit(CharLitNode node)
    {
        auto valType = new Type();
        valType.tag = TypeEnum.CHAR;
        builderStack[$-1] ~= valType;
    }

    void visit(StringLitNode node)
    {
        auto valType = new Type();
        valType.tag = TypeEnum.STRING;
        builderStack[$-1] ~= valType;
    }

    void visit(BooleanLiteralNode node)
    {
        auto valType = new Type();
        valType.tag = TypeEnum.BOOL;
        builderStack[$-1] ~= valType;
    }

    void visit(ArrayLiteralNode node)
    {
        node.children[0].accept(this);
        auto valType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        foreach (child; node.children[1..$])
        {
            child.accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!valType.cmp(nextType))
            {
                throw new Exception("Non-uniform type in array literal");
            }
        }
        auto arrayType = new ArrayType();
        arrayType.arrayType = valType;
        auto type = new Type();
        type.tag = TypeEnum.ARRAY;
        type.array = arrayType;
        builderStack[$-1] ~= type;
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
        writeln(format(funcScopes[$-1].syms));
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
                if (!decl.type.cmp(varType))
                {
                    throw new Exception("Type mismatch in tuple unpack.");
                }
            }
        }
        else
        {
            if (!decls[$-1].type.cmp(varType))
            {
                writeln(decls[$-1].type.format);
                writeln("vs.");
                writeln(varType.format);
                throw new Exception("Type mismatch in decl assignment.");
            }
        }
    }

    void visit(AssignExistingNode node)
    {
        lvalue = null;
        node.children[0].accept(this);
        auto left = lvalue;
        lvalue = null;
        auto op = (cast(ASTTerminal)node.children[1]).token;
        node.children[2].accept(this);
        auto varType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        final switch (op)
        {
        case "=":
            if (!left.cmp(varType))
            {
                throw new Exception("Type mismatch in assign-existing.");
            }
            break;
        case "+=":
        case "-=":
        case "/=":
        case "*=":
            if (!left.isNumeric || !varType.isNumeric)
            {
                throw new Exception("Non-numeric type in arithmetic assign-eq");
            }
            break;
        case "%=":
            if (!left.isIntegral || !varType.isIntegral)
            {
                throw new Exception("Non-integral type in mod-assign-eq");
            }
            break;
        case "~=":
            if (left.tag != TypeEnum.ARRAY)
            {
                throw new Exception("Cannot append-equal to non-array type");
            }
            else if (varType.tag == TypeEnum.ARRAY)
            {
                if (left.cmp(varType))
                {
                    break;
                }
                throw new Exception("Cannot append unlike array types");
            }
            else if (!left.array.arrayType.cmp(varType))
            {
                throw new Exception("Cannot append type to unlike array type");
            }
            break;
        }
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
        Type*[] types;
        foreach (child; node.children)
        {
            child.accept(this);
            types ~= builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
        }
        auto tuple = new TupleType();
        tuple.types = types;
        auto type = new Type;
        type.tag = TypeEnum.TUPLE;
        type.tuple = tuple;
        builderStack[$-1] ~= type;
    }

    void visit(LorRValueNode node)
    {
        node.children[0].accept(this);
        string varName = id;
        if (lvalue is null)
        {
            funcScopes.updateIfClosedOver(varName);
            auto lookup = funcScopes.scopeLookup(varName);
            if (!lookup.success)
            {
                throw new Exception("Cannot assign to undeclared variable.");
            }
            auto varType = funcScopes[lookup.funcIndex].syms[lookup.symIndex]
                                                       .decls[varName]
                                                       .type;
            lvalue = varType.copy;
        }
        // This means the varName is a member of whatever the current lvalue
        // type is
        else
        {
            switch (lvalue.tag)
            {
            case TypeEnum.STRUCT:
                foreach (member; lvalue.structDef.members)
                {
                    if (member.name == varName)
                    {
                        lvalue = member.type.copy;
                        break;
                    }
                }
                break;
            case TypeEnum.VARIANT:
                foreach (constructor; lvalue.variantDef.members)
                {
                    if (constructor.constructorName == varName)
                    {
                        lvalue = constructor.constructorElems.copy;
                        break;
                    }
                }
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

    void visit(LorRTrailerNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(LorRMemberAccessNode node)
    {
        node.children[0].accept(this);
    }

    void visit(SlicingNode node)
    {
        insideSlice++;
        // We're working on an lvalue
        if (lvalue !is null)
        {
            if (lvalue.tag != TypeEnum.ARRAY)
            {
                throw new Exception("Cannot slice non-array type.");
            }
            node.children[0].accept(this);
            auto sliceType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            // Single index, so not a slice. Else, we maintain the array
            // type, since we're just slicing, so leave lvalue as is
            if (sliceType.tag != TypeEnum.TUPLE)
            {
                lvalue = lvalue.array.arrayType;
            }
        }
        // We're working on an rvalue
        else
        {
            auto arrayType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (arrayType.tag != TypeEnum.ARRAY)
            {
                throw new Exception("Cannot slice non-array type.");
            }
            node.children[0].accept(this);
            auto sliceType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            // If it's not a range, then it's a single index, meaning a single
            // instance of what the array type contains
            if (sliceType.tag != TypeEnum.TUPLE)
            {
                builderStack[$-1] ~= arrayType.array.arrayType;
            }
            // Otherwise, it's a range, meaning the outgoing type is just the
            // array type again
            else
            {
                builderStack[$-1] ~= arrayType;
            }
        }
        insideSlice--;
    }

    void visit(SingleIndexNode node)
    {
        node.children[0].accept(this);
        auto indexType = builderStack[$-1][$-1];
        if (!indexType.isIntegral)
        {
            throw new Exception("Index type must be integral.");
        }
    }

    void visit(IndexRangeNode node)
    {
        node.children[0].accept(this);
    }

    void visit(StartToIndexRangeNode node)
    {
        node.children[0].accept(this);
        auto indexType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (!indexType.isIntegral)
        {
            throw new Exception("Index type must be integral.");
        }
        auto indexEnd = new Type();
        indexEnd.tag = TypeEnum.LONG;
        auto range = new TupleType();
        range.types = [indexType] ~ [indexEnd];
        auto wrap = new Type();
        wrap.tag = TypeEnum.TUPLE;
        wrap.tuple = range;
        builderStack[$-1] ~= wrap;
    }

    void visit(IndexToEndRangeNode node)
    {
        node.children[0].accept(this);
        auto indexType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (!indexType.isIntegral)
        {
            throw new Exception("Index type must be integral.");
        }
        auto indexEnd = new Type();
        indexEnd.tag = TypeEnum.LONG;
        auto range = new TupleType();
        range.types = [indexType] ~ [indexEnd];
        auto wrap = new Type();
        wrap.tag = TypeEnum.TUPLE;
        wrap.tuple = range;
        builderStack[$-1] ~= wrap;
    }

    void visit(IndexToIndexRangeNode node)
    {
        node.children[0].accept(this);
        auto indexStart = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (!indexStart.isIntegral)
        {
            throw new Exception("Index type must be integral.");
        }
        node.children[1].accept(this);
        auto indexEnd = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (!indexEnd.isIntegral)
        {
            throw new Exception("Index type must be integral.");
        }
        auto range = new TupleType();
        range.types = [indexStart] ~ [indexEnd];
        auto wrap = new Type();
        wrap.tag = TypeEnum.TUPLE;
        wrap.tuple = range;
        builderStack[$-1] ~= wrap;
    }

    void visit(TrailerNode node)
    {
        node.children[0].accept(this);
    }

    void visit(DynArrAccessNode node)
    {
        node.children[0].accept(this);
        if (node.children.length > 1)
        {
            node.children[1].accept(this);
        }
    }

    void visit(SliceLengthSentinelNode node)
    {
        if (insideSlice < 1)
        {
            throw new Exception("$ operator only valid inside slice");
        }
        auto valType = new Type();
        valType.tag = TypeEnum.INT;
        builderStack[$-1] ~= valType;
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
        builderStack[$-1] ~= instantiateAggregate(records, aggregate);
    }

    void visit(FuncCallTrailerNode node)
    {
        node.children[0].accept(this);
        if (node.children.length > 1)
        {
            node.children[1].accept(this);
        }
    }

    void visit(FuncCallArgListNode node)
    {
        // If we get here, then either curFuncCallSig is valid, or the top type
        // in the builder stack is using UFCS.
        if (curFuncCallSig !is null)
        {
            auto funcSig = curFuncCallSig;
            curFuncCallSig = null;
            auto funcArgs = funcSig.funcArgs;
            if (funcArgs.length != node.children.length)
            {
                throw new Exception("Incorrect number of arguments passed");
            }
            foreach (child, argExpected; lockstep(node.children, funcArgs))
            {
                child.accept(this);
                auto argPassed = builderStack[$-1][$-1];
                builderStack[$-1] = builderStack[$-1][0..$-1];
                if (!argPassed.cmp(argExpected.type))
                {
                    throw new Exception(
                        "Mismatch between expected and passed arg type");
                }
            }
            builderStack[$-1] ~= funcSig.returnType;
        }
    }

    void visit(FuncCallNode node)
    {
        node.children[0].accept(this);
        auto name = id;
        auto funcLookup = funcSigLookup(toplevelFuncs, name);
        if (!funcLookup.success)
        {
            throw new Exception("No function[" ~ name ~ "].");
        }
        else if (funcLookup.success)
        {
            curFuncCallSig = funcLookup.sig;
            node.children[1].accept(this);
        }
    }

    void visit(DotAccessNode node)
    {
        // Need to cover three cases:
        // First is handling the case of simply accessing a member value of the
        // type we're dot-accessing into.
        // Second, need to handle the case of accessing a member method of the
        // type.
        // Third, need to handle UFCS
        node.children[0].accept(this);
        auto name = id;
        auto curType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        // If the dot-access is with a struct, then we need to check if this is
        // any of all three of member method, member value, or UFCS (if the
        // function isn't a member function, but still takes the struct type
        // as it's first argument)
        if (curType.tag == TypeEnum.STRUCT)
        {}
        // It's some other type, meaning this must be UFCS
        else
        {
            auto funcLookup = funcSigLookup(toplevelFuncs, name);
            if (!funcLookup.success)
            {
                throw new Exception("No function[" ~ name ~ "].");
            }
            curFuncCallSig = funcLookup.sig;
            node.children[1].accept(this);
            // Finish this. Gotta actually determine whether the UFCS call works
        }
    }

    void visit(IfStmtNode node)
    {
        funcScopes[$-1].syms.length++;
        // CondAssignmentsNode
        node.children[0].accept(this);
        // BoolExprNode
        node.children[1].accept(this);
        auto boolType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (boolType.tag != TypeEnum.BOOL)
        {
            throw new Exception("Non-bool expr in if statement expr.");
        }
        // BareBlockNode
        node.children[2].accept(this);
        // ElseIfsNode
        node.children[3].accept(this);
        // ElseStmtNode
        node.children[4].accept(this);
        funcScopes[$-1].syms.length--;
    }

    void visit(ElseIfsNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(ElseIfStmtNode node)
    {
        node.children[0].accept(this);
        auto boolType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (boolType.tag != TypeEnum.BOOL)
        {
            throw new Exception("Non-bool expr in else if statement expr.");
        }
        node.children[1].accept(this);
    }

    void visit(ElseStmtNode node)
    {
        if (node.children.length > 0)
        {
            node.children[0].accept(this);
        }
    }

    void visit(WhileStmtNode node)
    {
        funcScopes[$-1].syms.length++;
        // CondAssignmentsNode
        node.children[0].accept(this);
        // BoolExprNode
        node.children[1].accept(this);
        auto boolType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (boolType.tag != TypeEnum.BOOL)
        {
            throw new Exception("Non-bool expr in while statement expr.");
        }
        // BareBlockNode
        node.children[2].accept(this);
        funcScopes[$-1].syms.length--;
    }

    void visit(CondAssignmentsNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(CondAssignNode node)
    {
        node.children[0].accept(this);
    }

    void visit(ForeachStmtNode node)
    {
        // ForeachArgsNode
        node.children[0].accept(this);
        // BoolExprNode
        node.children[1].accept(this);
        auto loopType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        Type*[] loopTypes;
        if (loopType.tag == TypeEnum.ARRAY)
        {
            loopTypes ~= loopType;
        }
        else if (loopType.tag == TypeEnum.TUPLE)
        {
            foreach (type; loopType.tuple.types)
            {
                if (type.tag != TypeEnum.ARRAY)
                {
                    throw new Exception(
                        "Cannot loop over non-array types in loop tuple");
                }
                loopTypes ~= type;
            }
        }
        else
        {
            throw new Exception("Cannot loop over non-array types");
        }
        if (foreachArgs.length != loopTypes.length)
        {
            throw new Exception("Foreach args must match loop types in number");
        }
        // Add the loop variables to the scope
        funcScopes[$-1].syms.length++;
        foreach (varName, type; lockstep(foreachArgs, loopTypes))
        {
            auto pair = new VarTypePair();
            pair.varName = varName;
            pair.type = type.array.arrayType;
            funcScopes[$-1].syms[$-1].decls[varName] = pair;
        }
        writeln(format(funcScopes[$-1].syms));
        // BareBlockNode
        node.children[2].accept(this);
        funcScopes[$-1].syms.length--;
    }

    void visit(ForeachArgsNode node)
    {
        foreachArgs = [];
        foreach (child; node.children)
        {
            child.accept(this);
            foreachArgs ~= id;
        }
    }

    void visit(ForStmtNode node) {}
    void visit(ForInitNode node) {}
    void visit(ForConditionalNode node) {}
    void visit(ForPostExpressionNode node) {}
    void visit(SpawnStmtNode node) {}
    void visit(YieldStmtNode node) {}
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
    void visit(ChanWriteNode node) {}
    void visit(ChanReadNode node) {}
    void visit(TemplateInstanceMaybeTrailerNode node) {}
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

    void visit(ASTTerminal node) {}
    void visit(AssignExistingOpNode node) {}
    void visit(StorageClassNode node) {}
    void visit(RefClassNode node) {}
    void visit(ConstClassNode node) {}
    void visit(FuncDefArgListNode node) {}
    void visit(FuncSigArgNode node) {}
    void visit(FuncReturnTypeNode node) {}
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
