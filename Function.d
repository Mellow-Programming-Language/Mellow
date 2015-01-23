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

auto format(TypeEnum tag)
{
    final switch (tag)
    {
    case TypeEnum.VOID:         return "VOID";
    case TypeEnum.LONG:         return "LONG";
    case TypeEnum.INT:          return "INT";
    case TypeEnum.SHORT:        return "SHORT";
    case TypeEnum.BYTE:         return "BYTE";
    case TypeEnum.FLOAT:        return "FLOAT";
    case TypeEnum.DOUBLE:       return "DOUBLE";
    case TypeEnum.CHAR:         return "CHAR";
    case TypeEnum.BOOL:         return "BOOL";
    case TypeEnum.STRING:       return "STRING";
    case TypeEnum.SET:          return "SET";
    case TypeEnum.HASH:         return "HASH";
    case TypeEnum.ARRAY:        return "ARRAY";
    case TypeEnum.AGGREGATE:    return "AGGREGATE";
    case TypeEnum.TUPLE:        return "TUPLE";
    case TypeEnum.FUNCPTR:      return "FUNCPTR";
    case TypeEnum.STRUCT:       return "STRUCT";
    case TypeEnum.VARIANT:      return "VARIANT";
    case TypeEnum.CHAN:         return "CHAN";
    }
}

class FunctionBuilder : Visitor
{
    private RecordBuilder records;
    private string id;
    private FuncSig*[] funcSigs;
    private FuncSig* curFuncCallSig;
    private string[] idTuple;
    private VarTypePair*[] funcArgs;
    private FuncSig*[] toplevelFuncs;
    // The higher the index, the deeper the scope
    private FunctionScope[] funcScopes;
    private VarTypePair*[] decls;
    private Type* lvalue;
    private Type* matchType;
    private uint insideSlice;
    private string[] foreachArgs;
    private uint[string] stackVarAllocSize;
    private string curFuncName;

    mixin TypeVisitors;

    FuncSig*[] getCompilableFuncSigs()
    {
        return toplevelFuncs.filter!(a => a.funcBodyBlocks !is null)
                            .array;
    }

    FuncSig*[] getExternFuncSigs()
    {
        return toplevelFuncs.filter!(a => a.funcBodyBlocks is null)
                            .array;
    }

    void updateFuncSigStackVarAllocSize()
    {
        foreach (sig; toplevelFuncs)
        {
            if (sig.funcName == curFuncName)
            {
                sig.stackVarAllocSize = stackVarAllocSize[curFuncName];
            }
        }
    }

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
            updateFuncSigStackVarAllocSize();
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
        funcSigs.length--;
        funcScopes.length--;
    }

    void visit(FuncSignatureNode node)
    {
        // Visit IdentifierNode, populate 'id'
        node.children[0].accept(this);
        auto funcName = id;
        this.curFuncName = funcName;
        this.stackVarAllocSize[curFuncName] = 0;
        auto lookup = funcSigLookup(toplevelFuncs, funcName);
        if (lookup.success)
        {
            funcSigs ~= lookup.sig;
            foreach (arg; lookup.sig.funcArgs)
            {
                stackVarAllocSize[curFuncName] += arg.type
                                                     .size
                                                     .stackAlignSize;
                funcScopes[$-1].syms[$-1].decls[arg.varName] = arg;
            }
        }
        // It must be an inner function definition
        else
        {

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
            if (!returnType.cmp(funcSigs[$-1].returnType))
            {
                throw new Exception("Wrong type for return.");
            }
        }
    }

    void visit(BoolExprNode node)
    {
        node.children[0].accept(this);
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(OrTestNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 1; i < node.children.length; i++)
        {
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (resultType.tag != TypeEnum.BOOL
                || nextType.tag != TypeEnum.BOOL)
            {
                throw new Exception("Non-bool type in LOGIC-OR.");
            }
        }
        builderStack[$-1] ~= resultType;
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(AndTestNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 1; i < node.children.length; i++)
        {
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (resultType.tag != TypeEnum.BOOL
                || nextType.tag != TypeEnum.BOOL)
            {
                throw new Exception("Non-bool type in LOGIC-AND.");
            }
        }
        builderStack[$-1] ~= resultType;
        node.data["type"] = builderStack[$-1][$-1];
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
        node.data["type"] = builderStack[$-1][$-1];
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
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(ExprNode node)
    {
        node.children[0].accept(this);
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(OrExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 1; i < node.children.length; i++)
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
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(XorExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 1; i < node.children.length; i++)
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
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(AndExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 1; i < node.children.length; i++)
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
        node.data["type"] = builderStack[$-1][$-1];
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
        node.data["type"] = builderStack[$-1][$-1];
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
                if (resultType.tag == TypeEnum.STRING)
                {
                    // We can only append a string or a char to a string, and
                    // the end result is always a string
                    if (nextType.tag != TypeEnum.CHAR
                        && nextType.tag != TypeEnum.STRING)
                    {
                        throw new Exception(
                            "String append without char or string."
                        );
                    }
                }
                else if (nextType.tag == TypeEnum.STRING)
                {
                    // We can only append a string or a char to a string, and
                    // the end result is always a string
                    if (resultType.tag != TypeEnum.CHAR
                        && resultType.tag != TypeEnum.STRING)
                    {
                        throw new Exception(
                            "String append without char or string."
                        );
                    }
                    resultType = nextType.copy;
                }
                else if (resultType.cmp(nextType))
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
        node.data["type"] = builderStack[$-1][$-1];
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
        node.data["type"] = builderStack[$-1][$-1];
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
                funcScopes.updateIfClosedOver(name);
                auto varType = funcScopes[varLookup.funcIndex]
                                    .syms[varLookup.symIndex]
                                    .decls[name]
                                    .type;
                builderStack[$-1] ~= varType;
            }
            else if (funcLookup.success)
            {
                curFuncCallSig = funcLookup.sig;
                auto funcPtr = new FuncPtrType();
                funcPtr.funcArgs = funcLookup.sig.funcArgs
                                                 .map!(a => a.type)
                                                 .array;
                funcPtr.returnType = funcLookup.sig.returnType;
                auto wrap = new Type;
                wrap.tag = TypeEnum.FUNCPTR;
                wrap.funcPtr = funcPtr;
                builderStack[$-1] ~= wrap;
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
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(ParenExprNode node)
    {
        node.children[0].accept(this);
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(NumberNode node)
    {
        node.children[0].accept(this);
        node.data["type"] = builderStack[$-1][$-1];
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
        node.data["type"] = builderStack[$-1][$-1];
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
        node.data["pair"] = pair;
        this.stackVarAllocSize[curFuncName] += varType.size
                                                      .stackAlignSize;
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
        foreach (decl; decls)
        {
            this.stackVarAllocSize[curFuncName] += decl.type
                                                       .size
                                                       .stackAlignSize;
        }
    }

    void visit(AssignExistingNode node)
    {
        node.children[0].accept(this);
        auto left = lvalue;
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
        Type*[] stackTypes;
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
            stackTypes ~= tupleTypes;
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
            stackTypes ~= varType;
        }
        foreach (type; stackTypes)
        {
            this.stackVarAllocSize[curFuncName] += type.size
                                                       .stackAlignSize;
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
        node.data["type"] = lvalue.copy;
        if (node.children.length > 1)
        {
            node.children[1].accept(this);
        }
    }

    void visit(LorRTrailerNode node)
    {
        if (lvalue.tag == TypeEnum.AGGREGATE)
        {
            lvalue = instantiateAggregate(records, lvalue.aggregate);
        }
        node.data["parenttype"] = lvalue;
        if (cast(IdentifierNode)node.children[0]) {
            if (lvalue.tag != TypeEnum.STRUCT)
            {
                throw new Exception("Member access only valid on struct type");
            }
            node.children[0].accept(this);
            auto memberName = id;
            bool found = false;
            foreach (member; lvalue.structDef.members)
            {
                if (memberName == member.name)
                {
                    found = true;
                    lvalue = member.type.copy;
                    node.data["type"] = member.type.copy;
                }
            }
            if (!found)
            {
                throw new Exception(memberName ~ " is not member of struct");
            }
            if (node.children.length > 1)
            {
                node.children[1].accept(this);
            }
        }
        else if (cast(SingleIndexNode)node.children[0]) {
            if (lvalue.tag != TypeEnum.ARRAY)
            {
                throw new Exception("Cannot index non-array type");
            }
            insideSlice++;
            node.children[0].accept(this);
            insideSlice--;
            lvalue = lvalue.array.arrayType.copy;
            node.data["type"] = lvalue.copy;
            if (node.children.length > 1)
            {
                node.children[1].accept(this);
            }
        }
    }

    void visit(SlicingNode node)
    {
        insideSlice++;
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
        // The type of the array we're indexing
        node.data["parenttype"] = builderStack[$-1][$-1];
        node.children[0].accept(this);
        if (node.children.length > 1)
        {
            node.children[1].accept(this);
        }
        // The type yielded after indexing
        node.data["type"] = builderStack[$-1][$-1];
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
        // Need to cover four cases:
        // First is handling the case of simply accessing a member value of the
        // type we're dot-accessing into.
        // Second, need to handle the case of accessing a member method of the
        // type.
        // Third, need to handle UFCS.
        // Fourth, need to handle compiler-supported members, like ".length"
        node.children[0].accept(this);
        auto name = id;
        auto curType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        node.data["type"] = curType.copy;
        if (curType.tag == TypeEnum.AGGREGATE)
        {
            curType = instantiateAggregate(records, curType.aggregate);
        }
        // If the dot-access is with a struct, then we need to check if this is
        // any of all three of member method, member value, or UFCS (if the
        // function isn't a member function, but still takes the struct type
        // as it's first argument)
        if (curType.tag == TypeEnum.STRUCT)
        {
            // First check to see if it's a data member
            bool found = false;
            foreach (member; curType.structDef.members)
            {
                if (name == member.name)
                {
                    found = true;
                    builderStack[$-1] ~= member.type.copy;
                }
            }
            if (!found)
            {
                throw new Exception(name ~ " is not member of struct");
            }

            // TODO check to see if it's a UFCS call or a member function call

            if (node.children.length > 1)
            {
                node.children[1].accept(this);
            }
        }
        else if (curType.tag == TypeEnum.ARRAY
            || curType.tag == TypeEnum.STRING)
        {
            // We're accessing the length property of arrays and strings
            if (name == "length")
            {
                auto longType = new Type();
                longType.tag = TypeEnum.INT;
                builderStack[$-1] ~= longType;
            }

            // TODO handle the case of UFCS

            else
            {

            }
        }
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

            // TODO Finish this. Gotta actually determine whether the UFCS call
            // works

        }
    }

    void visit(IfStmtNode node)
    {
        funcScopes[$-1].syms.length++;
        // CondAssignmentsNode
        node.children[0].accept(this);
        // BoolExprNode or IsExprNode
        node.children[1].accept(this);
        auto boolType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (boolType.tag != TypeEnum.BOOL)
        {
            throw new Exception("Non-bool expr in if statement expr.");
        }
        // BareBlockNode
        node.children[2].accept(this);
        funcScopes[$-1].syms.length--;
        // ElseIfsNode
        node.children[3].accept(this);
        // ElseStmtNode
        node.children[4].accept(this);
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
        funcScopes[$-1].syms.length++;
        // CondAssignmentsNode
        node.children[0].accept(this);
        // BoolExprNode or IsExprNode
        node.children[1].accept(this);
        auto boolType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (boolType.tag != TypeEnum.BOOL)
        {
            throw new Exception("Non-bool expr in if statement expr.");
        }
        // BareBlockNode
        node.children[2].accept(this);
        funcScopes[$-1].syms.length--;
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
        if (foreachArgs.length != loopTypes.length
            && foreachArgs.length - 1 != loopTypes.length)
        {
            throw new Exception(
                "Foreach args must match loop types in number, plus optional "
                "index counter"
            );
        }
        // Add the loop variables to the scope
        funcScopes[$-1].syms.length++;
        auto varUpdateArgs = foreachArgs;
        bool hasIndex = false;
        if (foreachArgs.length > loopTypes.length)
        {
            hasIndex = true;
            auto indexVarName = foreachArgs[0];
            // Skip the index arg for the following loop
            varUpdateArgs = foreachArgs[1..$];
            auto pair = new VarTypePair();
            pair.varName = indexVarName;
            auto indexType = new Type();
            indexType.tag = TypeEnum.INT;
            pair.type = indexType;
            funcScopes[$-1].syms[$-1].decls[indexVarName] = pair;
            this.stackVarAllocSize[curFuncName] += indexType.size
                                                            .stackAlignSize;
        }
        foreach (varName, type; lockstep(varUpdateArgs, loopTypes))
        {
            auto pair = new VarTypePair();
            pair.varName = varName;
            pair.type = type.array.arrayType;
            funcScopes[$-1].syms[$-1].decls[varName] = pair;
            this.stackVarAllocSize[curFuncName] += type.array
                                                       .arrayType
                                                       .size
                                                       .stackAlignSize;
        }
        // BareBlockNode
        node.children[2].accept(this);
        funcScopes[$-1].syms.length--;
        node.data["type"] = loopType;
        node.data["argnames"] = foreachArgs;
        node.data["hasindex"] = hasIndex;
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

    void visit(MatchStmtNode node)
    {
        funcScopes[$-1].syms.length++;
        // CondAssignmentsNode
        node.children[0].accept(this);
        // BoolExprNode
        node.children[1].accept(this);
        auto matchTypeSave = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        // MatchWhenNode+
        foreach (child; node.children[2..$])
        {
            funcScopes[$-1].syms.length++;
            matchType = matchTypeSave;
            child.accept(this);
            funcScopes[$-1].syms.length--;
        }
        funcScopes[$-1].syms.length--;
    }

    void visit(MatchWhenNode node)
    {
        // PatternNode
        node.children[0].accept(this);
        // StatementNode*
        foreach (child; node.children[1..$])
        {
            child.accept(this);
        }
    }

    void visit(PatternNode node)
    {
        node.children[0].accept(this);
    }

    void visit(DestructVariantPatternNode node)
    {
        if (matchType.tag != TypeEnum.VARIANT)
        {
            throw new Exception("Must match on " ~ matchType.tag.format
                ~ ", not variant type.");
        }
        matchType = normalizeVariantDefs(records, matchType.variantDef);
        // IdentifierNode
        node.children[0].accept(this);
        auto constructorName = id;
        // Try to grab the constructor with the same name. We'll get an array
        // with either that one member element, or it will be empty
        auto members = matchType.variantDef
                                .members
                                .filter!(a => a.constructorName
                                             == constructorName)
                                .array;
        if (members.length == 0)
        {
            throw new Exception("Variant constructor does not exist");
        }
        auto member = members[0];
        if (member.constructorElems.tuple.types.length
            != node.children[1..$].length)
        {
            throw new Exception("Pattern sub-element quantity mismatch");
        }
        foreach (child, subtype; lockstep(node.children[1..$],
                                        member.constructorElems.tuple.types))
        {
            matchType = subtype;
            child.accept(this);
        }
    }

    void visit(StructPatternNode node)
    {
        if (matchType.tag != TypeEnum.STRUCT)
        {
            throw new Exception("Must match on " ~ matchType.tag.format
                ~ ", not struct type.");
        }
    }

    void visit(BoolPatternNode node)
    {
        if (matchType.tag != TypeEnum.BOOL)
        {
            throw new Exception("Must match on " ~ matchType.tag.format
                ~ ", not bool type.");
        }
    }

    void visit(StringPatternNode node)
    {
        if (matchType.tag != TypeEnum.STRING)
        {
            throw new Exception("Must match on " ~ matchType.tag.format
                ~ ", not string type.");
        }
    }

    void visit(CharPatternNode node)
    {
        if (matchType.tag != TypeEnum.CHAR)
        {
            throw new Exception("Must match on " ~ matchType.tag.format
                ~ ", not char type.");
        }
    }

    void visit(IntPatternNode node)
    {
        if (!isIntegral(matchType))
        {
            throw new Exception("Must match on " ~ matchType.tag.format
                ~ ", not integer type.");
        }
    }

    void visit(FloatPatternNode node)
    {
        if (!isFloat(matchType))
        {
            throw new Exception("Must match on " ~ matchType.tag.format
                ~ ", not floating type.");
        }
    }

    void visit(TuplePatternNode node)
    {
        if (matchType.tag != TypeEnum.TUPLE)
        {
            throw new Exception("Must match on " ~ matchType.tag.format
                ~ ", not tuple type.");
        }
    }

    void visit(ArrayPatternNode node)
    {
        if (matchType.tag != TypeEnum.ARRAY)
        {
            throw new Exception("Must match on " ~ matchType.tag.format
                ~ ", not array type.");
        }
    }

    void visit(ArrayTailPatternNode node)
    {
        if (matchType.tag != TypeEnum.ARRAY)
        {
            throw new Exception("Must match on " ~ matchType.tag.format
                ~ ", not array type.");
        }
    }

    void visit(WildcardPatternNode node)
    {

    }

    void visit(VarOrBareVariantPatternNode node)
    {
        // IdentifierNode
        node.children[0].accept(this);
        auto var = id;
        auto maybeVariantDef = variantFromConstructor(records, var);
        if (maybeVariantDef !is null)
        {
            auto wrap = new Type();
            wrap.tag = TypeEnum.VARIANT;
            wrap.variantDef = maybeVariantDef;
            if (!wrap.cmp(matchType))
            {
                throw new Exception("Constructor for wrong variant definition");
            }
        }
        // Is a variable binding
        else
        {
            auto pair = new VarTypePair();
            pair.varName = var;
            pair.type = matchType.copy;
            funcScopes[$-1].syms[$-1].decls[var] = pair;
        }
    }

    void visit(IsExprNode node)
    {
        // BoolExprNode
        node.children[0].accept(this);
        // IdentifierNode
        node.children[1].accept(this);
        auto constructorName = id;
        auto variantDef = variantFromConstructor(records, constructorName);
        if (variantDef !is null)
        {
            auto members = variantDef.members
                                     .filter!(a => a.constructorName
                                                  == constructorName)
                                     .array;
            auto member = members[0];
            if (member.constructorElems.tag != TypeEnum.VOID)
            {
                if (member.constructorElems.tuple.types.length
                    != node.children[2..$].length)
                {
                    throw new Exception(
                        "Pattern sub-element quantity mismatch"
                    );
                }
                foreach (child, subtype;
                         lockstep(node.children[2..$],
                                  member.constructorElems.tuple.types))
                {
                    // Foreach type in the binding expression that is not a
                    // wildcard, bind the variable for use in the if statement
                    if (cast(IdentifierNode)child)
                    {
                        child.accept(this);
                        auto varBind = id;
                        auto pair = new VarTypePair();
                        pair.varName = varBind;
                        pair.type = subtype.copy;
                        funcScopes[$-1].syms[$-1].decls[varBind] = pair;
                    }
                }
            }
            auto boolType = new Type();
            boolType.tag = TypeEnum.BOOL;
            builderStack[$-1] ~= boolType;
        }
        else
        {
            throw new Exception("Variant constructor does not exist");
        }
    }

    // Note that in the syntax BoolExpr <-= BoolExpr, the left expression must
    // yield a chan-type that contains the same type as the type of the right
    // expression
    void visit(ChanWriteNode node)
    {
        // BoolExprNode
        node.children[0].accept(this);
        auto leftType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        // BoolExprNode
        node.children[1].accept(this);
        auto rightType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (leftType.tag != TypeEnum.CHAN)
        {
            throw new Exception("Can't chan-write to non-channel");
        }
        else if (!leftType.chan.chanType.cmp(rightType))
        {
            throw new Exception("Can't chan-write mismatched types");
        }
    }

    void visit(ChanReadNode node)
    {
        node.children[0].accept(this);
        auto type = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (type.tag != TypeEnum.CHAN)
        {
            throw new Exception("Cannot chan-read from non-channel");
        }
        builderStack[$-1] ~= type.chan.chanType.copy;
        node.data["type"] = type.chan.chanType.copy;
    }

    void visit(SpawnStmtNode node)
    {
        node.children[0].accept(this);
        auto name = id;
        auto funcLookup = funcSigLookup(toplevelFuncs, name);
        if (!funcLookup.success)
        {
            throw new Exception("No function " ~ name ~ " to spawn");
        }
        if (funcLookup.sig.returnType.tag != TypeEnum.VOID)
        {
            throw new Exception("Cannot spawn non-void function");
        }
        curFuncCallSig = funcLookup.sig;
        node.data["sig"] = funcLookup.sig;
        node.children[1].accept(this);
    }

    void visit(YieldStmtNode node)
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
    void visit(TemplateInstanceMaybeTrailerNode node) {}

    void visit(ASTTerminal node) {}
    // Note that we must cater to the whims of updating
    // this.stackVarAllocSize[curFuncName] with the stack sizes of each variable
    // declared in this expression
    void visit(VariantIsMatchNode node) {}
    void visit(IdOrWildcardNode node) {}
    void visit(AssignExistingOpNode node) {}
    void visit(StorageClassNode node) {}
    void visit(ConstClassNode node) {}
    void visit(ExternStructDeclNode node) {}
    void visit(ExternFuncDeclNode node) {}
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
