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
import TemplateInstantiator;

// CLosures and struct member functions can be implemented in exactly the same
// way. The 'this' pointer and the environment pointer for closures are
// identical, as long as the pointer points to a block of memory where each
// variable is allocated. That is, a struct reference pointer is simply a
// pointer to memory where each member is allocated sequentially. If the
// environment pointer follows the same pattern, then the implementation for
// each is the same, and perhaps building the datastructures for handling them
// in the compiler can be the same as well

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
    private FuncSig*[] toplevelFuncs;
    private FuncSig*[] importedFuncSigs;
    private FuncSig*[] funcSigs;
    private FuncSig*[] callSigs;
    private FuncSig* curFuncCallSig;
    private string[] idTuple;
    private VarTypePair*[] funcArgs;
    // The higher the index, the deeper the scope
    private FunctionScope[] funcScopes;
    private VarTypePair*[] decls;
    private Type* lvalue;
    private Type* matchType;
    private uint insideSlice;
    private string[] foreachArgs;
    private uint[string] stackVarAllocSize;
    private string curFuncName;
    private Type* curVariant;
    private string curConstructor;
    private bool skipTemplatedFuncDef;
    private ProgramNode topNode;

    mixin TypeVisitors;

    FuncSig*[] getCompilableFuncSigs()
    {
        // Get all functions that have a compilable function body, AND
        // which are not base function templates, ie, have a mangled name
        return toplevelFuncs.filter!(a => a.funcDefNode !is null)
                            .filter!(a => a.templateParams.length == 0
                                       || (a.funcName.length >= 3
                                        && a.funcName[0..2] == "__"))
                            .array;
    }

    FuncSig*[] getExternFuncSigs()
    {
        return toplevelFuncs.filter!(a => a.funcDefNode is null)
                            .array ~ importedFuncSigs;
    }

    // TODO update this so templated functions are handled correctly, ie, their
    // mangled names
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

    this (ProgramNode node, RecordBuilder records, FuncSig*[] sigs,
          FuncSig*[] importedFuncSigs)
    {
        this.topNode = node;
        this.records = records;
        this.toplevelFuncs = sigs;
        this.importedFuncSigs = importedFuncSigs;
        builderStack.length++;
        for (auto i = 0; i < node.children.length; i++)
        {
            if (cast(FuncDefNode)node.children[i])
            {
                node.children[i].accept(this);
            }
        }
        insideSlice = 0;
    }

    void visit(FuncDefNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncDefNode"));
        funcScopes.length++;
        funcScopes[$-1].syms.length++;
        // Visit FuncSignatureNode
        skipTemplatedFuncDef = false;
        node.children[0].accept(this);
        if (skipTemplatedFuncDef)
        {
            return;
        }
        // Visit FuncBodyBlocksNode
        node.children[1].accept(this);
        funcSigs.length--;
        funcScopes.length--;
        updateFuncSigStackVarAllocSize();
    }

    void visit(FuncSignatureNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncSignatureNode"));
        // Visit IdentifierNode, populate 'id'
        node.children[0].accept(this);
        auto funcName = id;
        this.curFuncName = funcName;
        if ((cast(TemplateTypeParamsNode)node.children[1]).children.length > 0)
        {
            // This is a templated function, so we don't try to typecheck it
            // until it's been instantiated
            skipTemplatedFuncDef = true;
            return;
        }
        this.stackVarAllocSize[curFuncName] = 0;
        auto lookup = funcSigLookup(
            toplevelFuncs ~ importedFuncSigs, funcName
        );
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
        funcScopes[$-1].syms.length++;
        foreach (child; node.children)
        {
            child.accept(this);
        }
        debug (TYPECHECK) funcScopes[$-1].syms.format.writeln;
        funcScopes[$-1].syms.length--;
    }

    void visit(StatementNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("StatementNode"));
        node.children[0].accept(this);
    }

    void visit(ReturnStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ReturnStmtNode"));
        if (node.children.length > 0)
        {
            node.children[0].accept(this);
            auto returnType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!returnType.cmp(funcSigs[$-1].returnType.copy))
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Wrong type for return in function ["
                    ~ funcSigs[$-1].funcName ~ "]:\n"
                    ~ "  Expects: " ~ funcSigs[$-1].returnType.format ~ "\n"
                    ~ "  But got: " ~ returnType.format
                );
            }
        }
    }

    void visit(BoolExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("BoolExprNode"));
        node.children[0].accept(this);
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(OrTestNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("OrTestNode"));
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
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Non-bool type in LOGIC-OR in function ["
                    ~ funcSigs[$-1].funcName ~ "]"
                );
            }
        }
        builderStack[$-1] ~= resultType;
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(AndTestNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("AndTestNode"));
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
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Non-bool type in LOGIC-AND in function ["
                    ~ funcSigs[$-1].funcName ~ "]"
                );
            }
        }
        builderStack[$-1] ~= resultType;
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(NotTestNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("NotTestNode"));
        node.children[0].accept(this);
        if (typeid(node.children[0]) == typeid(NotTestNode))
        {
            if (builderStack[$-1][$-1].tag != TypeEnum.BOOL)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Cannot negate non-bool type in function ["
                    ~ funcSigs[$-1].funcName ~ "]"
                );
            }
        }
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(ComparisonNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ComparisonNode"));
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
            case "==":
            case "!=":
                if (resultType.isNumeric && nextType.isNumeric) {}
                else if (resultType.cmp(nextType) &&
                      (resultType.tag == TypeEnum.CHAR
                    || resultType.tag == TypeEnum.BOOL
                    || resultType.tag == TypeEnum.STRING)) {}
                else
                {
                    throw new Exception(
                        errorHeader(node) ~ "\n"
                        ~ "Mismatched types for equality cmp in function ["
                        ~ funcSigs[$-1].funcName ~ "]\n"
                        ~ "Left Type : " ~ resultType.format ~ "\n"
                        ~ "Right Type: " ~ nextType.format
                    );
                }
                break;
            case "<in>":
                if (resultType.tag != TypeEnum.SET
                    || nextType.tag != TypeEnum.SET
                    || !resultType.set.setType.cmp(nextType.set.setType))
                {
                    throw new Exception(
                        errorHeader(node) ~ "\n"
                        ~ "Mismatched types in `<in>` op in function ["
                        ~ funcSigs[$-1].funcName ~ "]\n"
                        ~ "Left Type : " ~ resultType.format ~ "\n"
                        ~ "Right Type: " ~ nextType.format
                    );
                }
                break;
            case "in":
                if (nextType.tag != TypeEnum.SET
                    || !nextType.set.setType.cmp(resultType))
                {
                    throw new Exception(
                        errorHeader(node) ~ "\n"
                        ~ "Mismatched types in `in` op in function ["
                        ~ funcSigs[$-1].funcName ~ "]\n"
                        ~ "Left Type : " ~ resultType.format ~ "\n"
                        ~ "Right Type: " ~ nextType.format
                    );
                }
                break;
            }
            node.data["lefttype"] = resultType;
            node.data["righttype"] = nextType;
            auto boolType = new Type();
            boolType.tag = TypeEnum.BOOL;
            resultType = boolType;
        }
        builderStack[$-1] ~= resultType;
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(ExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ExprNode"));
        node.children[0].accept(this);
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(OrExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("OrExprNode"));
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
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Non-integral type in BIT-OR operation in function ["
                    ~ funcSigs[$-1].funcName ~ "]"
                );
            }
        }
        builderStack[$-1] ~= resultType;
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(XorExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("XorExprNode"));
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
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Non-integral type in BIT-XOR operation in function ["
                    ~ funcSigs[$-1].funcName ~ "]"
                );
            }
        }
        builderStack[$-1] ~= resultType;
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(AndExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("AndExprNode"));
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
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Non-integral type in BIT-AND operation in function ["
                    ~ funcSigs[$-1].funcName ~ "]"
                );
            }
        }
        builderStack[$-1] ~= resultType;
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(ShiftExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ShiftExprNode"));
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
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Non-integral type in shift operation in function ["
                    ~ funcSigs[$-1].funcName ~ "]"
                );
            }
        }
        builderStack[$-1] ~= resultType;
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(SumExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("SumExprNode"));
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
                resultType = promoteNumeric(
                    resultType, nextType, node.children[i-1]
                );
                break;
            case "<|>":
            case "<&>":
            case "<^>":
            case "<->":
                if (!resultType.cmp(nextType)
                    || resultType.tag != TypeEnum.SET
                    || nextType.tag != TypeEnum.SET)
                {
                    throw new Exception(
                        errorHeader(node) ~ "\n"
                        ~ "Type mismatch in set operation."
                    );
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
                            errorHeader(node) ~ "\n"
                            ~ "String append without char or string."
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
                            errorHeader(node) ~ "\n"
                            ~ "String append without char or string."
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
                                errorHeader(node) ~ "\n"
                                ~ "Cannot append type to unlike array type\n"
                                ~ "Left : " ~ resultType.format ~ "\n"
                                ~ "Right: " ~ nextType.format
                            );
                        }
                    }
                    else if (nextType.tag == TypeEnum.ARRAY)
                    {
                        if (!nextType.array.arrayType.cmp(resultType))
                        {
                            throw new Exception(
                                errorHeader(node) ~ "\n"
                                ~ "Cannot append type to unlike array type\n"
                                ~ "Left : " ~ resultType.format ~ "\n"
                                ~ "Right: " ~ nextType.format
                            );
                        }
                        resultType = nextType;
                    }
                    else
                    {
                        throw new Exception(
                            errorHeader(node) ~ "\n"
                            ~ "Cannot append two unlike, non-array types.\n"
                            ~ "Left : " ~ resultType.format ~ "\n"
                            ~ "Right: " ~ nextType.format
                        );
                    }
                }
            }
        }
        builderStack[$-1] ~= resultType;
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(ProductExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ProductExprNode"));
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
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Cannot perform " ~ op ~ " on non-arith."
                );
            }
            if (op == "%" && (resultType.isFloat || nextType.isFloat))
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "% (modulus) undefined for float types."
                );
            }
            resultType = promoteNumeric(
                resultType, nextType, node.children[i-1]
            );
        }
        builderStack[$-1] ~= resultType;
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(ValueNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ValueNode"));
        FuncSig* localFuncSig;
        if (typeid(node.children[0]) == typeid(IdentifierNode))
        {
            node.children[0].accept(this);
            auto name = id;
            auto varLookup = funcScopes.scopeLookup(name);
            auto funcLookup = funcSigLookup(
                toplevelFuncs ~ importedFuncSigs, name
            );
            auto variant = variantFromConstructor(records, name);
            if (!varLookup.success && !funcLookup.success && variant is null)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "No variable, function, or variant constructor ["
                    ~ name ~ "] in function ["
                    ~ funcSigs[$-1].funcName ~ "]"
                );
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
                localFuncSig = curFuncCallSig;
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
            else if (variant !is null)
            {
                if (variant.templateParams.length > 0)
                {
                    if (node.children.length == 1
                        || cast(TemplateInstanceMaybeTrailerNode)
                          (cast(TrailerNode)node.children[1]).children[0]
                           is null)
                    {
                        throw new Exception(
                            errorHeader(node) ~ "\n"
                            ~ "Cannot instantiate templated variant "
                            ~ "constructor ["
                            ~ name
                            ~ "] of variant ["
                            ~ variant.format
                            ~ "] without a template instantiation in function ["
                            ~ funcSigs[$-1].funcName ~ "]"
                        );
                    }
                }
                curVariant = new Type();
                curVariant.tag = TypeEnum.VARIANT;
                curVariant.variantDef = variant;
                curConstructor = name;
                builderStack[$-1] ~= curVariant;
            }
            if (node.children.length > 1)
            {
                node.children[1].accept(this);
                if (localFuncSig !is null
                    && localFuncSig.templateParams.length > 0
                    && callSigs.length > 0)
                {
                    auto newIdNode = new IdentifierNode();
                    auto terminal = new ASTTerminal(
                        callSigs[$-1].funcName, 0
                    );
                    callSigs.length--;
                    newIdNode.children ~= terminal;
                    node.children[0] = newIdNode;
                }
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
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ParenExprNode"));
        node.children[0].accept(this);
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(NumberNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("NumberNode"));
        node.children[0].accept(this);
        node.data["type"] = builderStack[$-1][$-1];
    }

    void visit(IntNumNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("IntNumNode"));
        auto valType = new Type();
        valType.tag = TypeEnum.INT;
        builderStack[$-1] ~= valType;
    }

    void visit(FloatNumNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FloatNumNode"));
        auto valType = new Type();
        valType.tag = TypeEnum.FLOAT;
        builderStack[$-1] ~= valType;
    }

    void visit(CharLitNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("CharLitNode"));
        auto valType = new Type();
        valType.tag = TypeEnum.CHAR;
        builderStack[$-1] ~= valType;
    }

    void visit(StringLitNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("StringLitNode"));
        auto valType = new Type();
        valType.tag = TypeEnum.STRING;
        builderStack[$-1] ~= valType;
    }

    void visit(BooleanLiteralNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("BooleanLiteralNode"));
        auto valType = new Type();
        valType.tag = TypeEnum.BOOL;
        builderStack[$-1] ~= valType;
    }

    void visit(StructConstructorNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("StructConstructorNode"));
        node.children[0].accept(this);
        auto structName = id;
        auto i = 1;
        // Instantiate the actual struct type, including template arguments
        auto aggregate = new AggregateType();
        aggregate.typeName = structName;
        if (cast(TemplateInstantiationNode)node.children[1])
        {
            i = 2;
            builderStack.length++;
            node.children[1].accept(this);
            aggregate.templateInstantiations = builderStack[$-1];
            builderStack.length--;
        }
        auto structDef = instantiateAggregate(records, aggregate);
        Type*[string] memberAssigns;
        for (; i < node.children.length; i += 2)
        {
            node.children[i].accept(this);
            auto memberName = id;
            node.children[i+1].accept(this);
            auto valType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (memberName in memberAssigns)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "A struct member must appear only once in a constructor"
                );
            }
            memberAssigns[memberName] = valType;
        }
        Type*[string] membersActual;
        foreach (member; structDef.structDef.members)
        {
            membersActual[member.name] = member.type.normalize(records);
        }
        auto memberNamesAssigned = memberAssigns.keys
                                                .sort;
        auto memberNamesActual = membersActual.keys
                                              .sort;
        if (memberNamesAssigned.sort
                               .setSymmetricDifference(memberNamesActual.sort)
                               .walkLength > 0)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Incorrect struct member arguments in constructor"
            );
        }
        foreach (key; memberAssigns.keys)
        {
            auto assignedType = memberAssigns[key];
            auto expectedType = membersActual[key];
            // Handle case of instantiating array as "[]"
            if (assignedType.tag == TypeEnum.ARRAY
                && assignedType.array.arrayType.tag == TypeEnum.VOID
                && expectedType.tag == TypeEnum.ARRAY)
            {
                assignedType = expectedType.copy;
            }
            if (!assignedType.cmp(expectedType))
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Type mismatch in struct constructor:\n"
                    ~ "  Member [" ~ key ~ "]\n"
                    ~ "  Expects type: " ~ expectedType.format ~ "\n"
                    ~ "  But got type: " ~ assignedType.format
                );
            }
        }
        node.data["type"] = structDef;
        builderStack[$-1] ~= structDef;
    }

    void visit(StructMemberConstructorNode node) {}

    void visit(ArrayLiteralNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ArrayLiteralNode"));
        auto arrayType = new ArrayType();
        auto type = new Type();
        if (node.children.length == 0)
        {
            auto voidType = new Type();
            voidType.tag = TypeEnum.VOID;
            arrayType.arrayType = voidType;
        }
        else
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
                    throw new Exception(
                        errorHeader(node) ~ "\n"
                        ~ "Non-uniform type in array literal in function ["
                        ~ funcSigs[$-1].funcName ~ "]"
                    );
                }
            }
            arrayType.arrayType = valType;
        }
        type.tag = TypeEnum.ARRAY;
        type.array = arrayType;
        builderStack[$-1] ~= type;
        node.data["type"] = builderStack[$-1][$-1];
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
        if (varType.tag == TypeEnum.AGGREGATE
            || varType.tag == TypeEnum.STRUCT
            || varType.tag == TypeEnum.VARIANT)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Cannot declare but not initialize struct or variant types.\n"
                ~ "  For [" ~ varName ~ ": " ~ varType.format ~ ";]\n"
                ~ "  Use the appropriate value constructor"
            );
        }
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
        decls = [];
    }

    void visit(DeclAssignmentNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("DeclAssignmentNode"));
        node.children[0].accept(this);
        node.children[1].accept(this);
        auto varType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (varType.tag == TypeEnum.TUPLE)
        {
            auto tupleTypes = varType.tuple.types;
            if (tupleTypes.length != decls.length)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Tuple member count mismatch."
                );
            }
            foreach (decl, varType; lockstep(decls, tupleTypes))
            {
                if (!decl.type.cmp(varType))
                {
                    throw new Exception(
                        errorHeader(node) ~ "\n"
                        ~ "Type mismatch in tuple unpack."
                    );
                }
            }
        }
        else
        {
            if (varType.tag == TypeEnum.ARRAY
                && varType.array.arrayType.tag == TypeEnum.VOID
                && decls[$-1].type.tag == TypeEnum.ARRAY)
            {
                varType = decls[$-1].type.copy;
            }
            if (!decls[$-1].type.cmp(varType))
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Type mismatch in decl assignment.\n"
                    ~ "Expects: " ~ decls[$-1].type.format ~ "\n"
                    ~ "But got: " ~ varType.format
                );
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
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("AssignExistingNode"));
        node.children[0].accept(this);
        auto left = lvalue;
        auto op = (cast(ASTTerminal)node.children[1]).token;
        node.children[2].accept(this);
        auto varType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        // Cover the case of assigning an empty array literal
        if (varType.tag == TypeEnum.ARRAY
            && varType.array.arrayType.tag == TypeEnum.VOID
            && left.tag == TypeEnum.ARRAY)
        {
            varType = left.copy;
        }
        final switch (op)
        {
        case "=":
            if (!left.cmp(varType))
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Type mismatch in assign-existing in function ["
                    ~ funcSigs[$-1].funcName ~ "]\n"
                    ~ "  Expects: " ~ left.format ~ "\n"
                    ~ "  But got: " ~ varType.format
                );
            }
            break;
        case "+=":
        case "-=":
        case "/=":
        case "*=":
            if (!left.isNumeric || !varType.isNumeric)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Non-numeric type in arithmetic assign-eq"
                );
            }
            break;
        case "%=":
            if (!left.isIntegral || !varType.isIntegral)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Non-integral type in mod-assign-eq"
                );
            }
            break;
        case "~=":
            if (left.tag != TypeEnum.ARRAY)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Cannot append-equal to non-array type"
                );
            }
            else if (varType.tag == TypeEnum.ARRAY)
            {
                if (left.cmp(varType))
                {
                    break;
                }
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Cannot append unlike array types"
                );
            }
            else if (!left.array.arrayType.cmp(varType))
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Cannot append type to unlike array type"
                );
            }
            break;
        }
    }

    void visit(DeclTypeInferNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("DeclTypeInferNode"));
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
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Non-Tuple type!"
                );
            }
            auto tupleTypes = varTuple.tuple.types;
            if (tupleTypes.length != varNames.length)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Tuple member count mismatch."
                );
            }
            foreach (varName, varType; lockstep(varNames, tupleTypes))
            {
                if (varType.tag == TypeEnum.ARRAY
                    && varType.array.arrayType.tag == TypeEnum.VOID)
                {
                    throw new Exception(
                        errorHeader(node) ~ "\n"
                        ~ "Cannot infer contained type of empty array literal"
                    );
                }
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
            if (varType.tag == TypeEnum.ARRAY
                && varType.array.arrayType.tag == TypeEnum.VOID)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Cannot infer contained type of empty array literal"
                );
            }
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
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("AssignmentNode"));
        node.children[0].accept(this);
    }

    void visit(ValueTupleNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ValueTupleNode"));
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
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("LorRValueNode"));
        node.children[0].accept(this);
        string varName = id;
        funcScopes.updateIfClosedOver(varName);
        auto lookup = funcScopes.scopeLookup(varName);
        if (!lookup.success)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Cannot assign to undeclared variable."
            );
        }
        auto varType = funcScopes[lookup.funcIndex].syms[lookup.symIndex]
                                                   .decls[varName]
                                                   .type;
        lvalue = varType.normalize(records);
        node.data["type"] = lvalue;
        if (node.children.length > 1)
        {
            node.children[1].accept(this);
        }
    }

    void visit(LorRTrailerNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("LorRTrailerNode"));
        node.data["parenttype"] = lvalue;
        if (cast(IdentifierNode)node.children[0]) {
            if (lvalue.tag != TypeEnum.STRUCT)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Member access only valid on struct type"
                );
            }
            node.children[0].accept(this);
            auto memberName = id;
            bool found = false;
            foreach (member; lvalue.structDef.members)
            {
                if (memberName == member.name)
                {
                    found = true;
                    lvalue = member.type.normalize(records);
                    node.data["type"] = lvalue;
                }
            }
            if (!found)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ memberName ~ " is not member of struct"
                );
            }
            if (node.children.length > 1)
            {
                node.children[1].accept(this);
            }
        }
        else if (cast(SingleIndexNode)node.children[0])
        {
            if (lvalue.tag == TypeEnum.STRING)
            {
                throw new Exception(
                    "Cannot lvalue index immutable type [string].\n"
                    ~ "Consider using [stringToChars()] and "
                    ~ "[charsToString()] in [std.conv]"
                );
            }
            else if (lvalue.tag != TypeEnum.ARRAY)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Cannot lvalue index non-array type ["
                    ~ lvalue.format ~ "]"
                );
            }
            insideSlice++;
            node.children[0].accept(this);
            insideSlice--;
            lvalue = lvalue.array.arrayType.normalize(records);
            node.data["type"] = lvalue;
            if (node.children.length > 1)
            {
                node.children[1].accept(this);
            }
        }
    }

    void visit(SlicingNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("SlicingNode"));
        insideSlice++;
        auto arrayType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (arrayType.tag != TypeEnum.ARRAY
            && arrayType.tag != TypeEnum.STRING)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Cannot slice non-array, non-string type."
            );
        }
        node.children[0].accept(this);
        auto sliceType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        // If it's not a range, then it's a single index, meaning a single
        // instance of what the array type contains
        if (sliceType.tag != TypeEnum.TUPLE)
        {
            // If it's a string, then the single index type is char
            if (arrayType.tag == TypeEnum.STRING)
            {
                auto charType = new Type();
                charType.tag = TypeEnum.CHAR;
                builderStack[$-1] ~= charType;
            }
            else
            {
                builderStack[$-1] ~= arrayType.array.arrayType;
            }
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
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("SingleIndexNode"));
        node.children[0].accept(this);
        auto indexType = builderStack[$-1][$-1];
        if (!indexType.isIntegral)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Index type must be integral."
            );
        }
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
        auto indexType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (!indexType.isIntegral)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Index type must be integral."
            );
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
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("IndexToEndRangeNode"));
        node.children[0].accept(this);
        auto indexType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (!indexType.isIntegral)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Index type must be integral."
            );
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
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("IndexToIndexRangeNode"));
        node.children[0].accept(this);
        auto indexStart = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (!indexStart.isIntegral)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Index type must be integral."
            );
        }
        node.children[1].accept(this);
        auto indexEnd = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (!indexEnd.isIntegral)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Index type must be integral."
            );
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
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("TrailerNode"));
        node.children[0].accept(this);
    }

    void visit(DynArrAccessNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("DynArrAccessNode"));
        // The type of the array we're indexing
        node.data["parenttype"] = builderStack[$-1][$-1];
        node.children[0].accept(this);
        // The type yielded after indexing
        node.data["type"] = builderStack[$-1][$-1];
        if (node.children.length > 1)
        {
            node.children[1].accept(this);
        }
    }

    void visit(TemplateInstanceMaybeTrailerNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("TemplateInstanceMaybeTrailerNode"));
        builderStack.length++;
        node.children[0].accept(this);
        auto templateInstantiations = builderStack[$-1];
        builderStack.length--;
        if (curFuncCallSig !is null)
        {
            auto instantiator = new TemplateInstantiator(records);
            curFuncCallSig = instantiator.instantiateFunction(
                curFuncCallSig, templateInstantiations
            );
            auto funcLookup = funcSigLookup(
                toplevelFuncs ~ importedFuncSigs, curFuncCallSig.funcName
            );
            if (!funcLookup.success)
            {
                toplevelFuncs ~= curFuncCallSig;
                // Add this instantiated, templated function to the end of the
                // abstract syntax tree, effectively bringing it into existence,
                // and allowing it to get typechecked later
                topNode.children ~= curFuncCallSig.funcDefNode;
            }
            callSigs ~= curFuncCallSig;
        }
        else if (curVariant !is null)
        {
            Type*[string] mappings;
            foreach (name, type; lockstep(curVariant.variantDef.templateParams,
                                          templateInstantiations))
            {
                mappings[name] = type;
            }
            curVariant = curVariant.instantiateTypeTemplate(mappings, records);
            // If this is a template instantation of a templated constructor
            // that contains no member values, add the type to the stack
            if (node.children.length == 1)
            {
                // Take off the preliminary variant from the type stack, that
                // was placed there in the ValueNode visit() function in case
                // it was a value-less variant constructor
                builderStack[$-1] = builderStack[$-1][0..$-1];
                builderStack[$-1] ~= curVariant;
            }
        }
        if (node.children.length > 1)
        {
            node.children[1].accept(this);
        }
    }

    void visit(SliceLengthSentinelNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("SliceLengthSentinelNode"));
        if (insideSlice < 1)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "$ operator only valid inside slice"
            );
        }
        auto valType = new Type();
        valType.tag = TypeEnum.INT;
        builderStack[$-1] ~= valType;
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
        auto wrap = new Type();
        wrap.tag = TypeEnum.AGGREGATE;
        wrap.aggregate = aggregate;
        auto normalized = normalize(wrap, records);
        builderStack[$-1] ~= normalized;
    }

    void visit(FuncCallTrailerNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncCallTrailerNode"));
        node.data["funcsig"] = curFuncCallSig;
        node.children[0].accept(this);
        if (node.children.length > 1)
        {
            node.children[1].accept(this);
        }
    }

    void visit(FuncCallArgListNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncCallArgListNode"));
        // If we get here, then either curFuncCallSig is valid, or the top type
        // in the builder stack is using UFCS.
        if (curFuncCallSig !is null)
        {
            node.data["case"] = "funccall";
            auto funcSig = curFuncCallSig;
            curFuncCallSig = null;
            auto funcArgs = funcSig.funcArgs;
            if (funcArgs.length != node.children.length)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Incorrect number of arguments passed for call of "
                    ~ "function [" ~ funcSig.funcName ~ "] in function ["
                    ~ funcSigs[$-1].funcName ~ "]"
                );
            }
            foreach (i, child, argExpected; lockstep(node.children, funcArgs))
            {
                child.accept(this);
                auto argPassed = builderStack[$-1][$-1];
                builderStack[$-1] = builderStack[$-1][0..$-1];
                argExpected.type = normalize(argExpected.type, records);
                // Reconcile case of having passed a "[]" as an array literal
                // for this argument to the function
                if (argPassed.tag == TypeEnum.ARRAY
                    && argPassed.array.arrayType.tag == TypeEnum.VOID
                    && argExpected.type.tag == TypeEnum.ARRAY)
                {
                    argPassed = argExpected.type.copy;
                }
                if (!argPassed.cmp(argExpected.type))
                {
                    throw new Exception(
                        errorHeader(node) ~ "\n"
                        ~ "Mismatch between expected and passed arg type for "
                        ~ "call of function [" ~ funcSig.funcName
                        ~ "] in function [" ~ funcSigs[$-1].funcName ~ "]\n"
                        ~ "  Expects: " ~ argExpected.type.format ~ "\n"
                        ~ "  But got: " ~ argPassed.format ~ "\n"
                        ~ "in arg position [" ~ i.to!string ~ "]"
                    );
                }
            }
            builderStack[$-1] ~= funcSig.returnType;
        }
        else if (curVariant !is null)
        {
            node.data["case"] = "variant";
            node.data["parenttype"] = curVariant;
            node.data["constructor"] = curConstructor;
            auto variant = curVariant;
            curVariant = null;
            auto member = variant.variantDef.getMember(curConstructor);
            if (member.constructorElems.tag == TypeEnum.VOID)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Constructor [" ~ curConstructor
                                   ~ "] of variant ["
                                   ~ variant.variantDef.format
                                   ~ "] cannot have value arguments"
                );
            }
            auto expectedTypes = member.constructorElems
                                       .tuple
                                       .types;
            foreach (child, typeExpected; lockstep(node.children,
                                                   expectedTypes))
            {
                child.accept(this);
                auto typeGot = builderStack[$-1][$-1];
                builderStack[$-1] = builderStack[$-1][0..$-1];
                typeExpected = normalize(typeExpected, records);
                // Reconcile case of passing empty array literal "[]" as value
                // in instantiating this variant constructor
                if (typeGot.tag == TypeEnum.ARRAY
                    && typeGot.array.arrayType.tag == TypeEnum.VOID
                    && typeExpected.tag == TypeEnum.ARRAY)
                {
                    typeGot = typeExpected.copy;
                }
                if (!typeExpected.cmp(typeGot))
                {
                    throw new Exception(
                        errorHeader(node) ~ "\n"
                        ~ "Mismatch between expected and passed variant "
                        "constructor instantiation type: \n"
                      ~ "  Expected: " ~ typeExpected.formatFull ~ "\n"
                      ~ "  Got: " ~ typeGot.formatFull
                    );
                }
            }
            // Take off the preliminary variant from the type stack, that
            // was placed there in the ValueNode visit() function in case
            // it was a value-less variant constructor
            builderStack[$-1] = builderStack[$-1][0..$-1];
            builderStack[$-1] ~= variant;
        }
    }

    void visit(FuncCallNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FuncCallNode"));
        node.children[0].accept(this);
        auto name = id;
        auto funcLookup = funcSigLookup(
            toplevelFuncs ~ importedFuncSigs, name
        );
        if (!funcLookup.success)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "No function[" ~ name ~ "]."
            );
        }
        curFuncCallSig = funcLookup.sig;
        if (cast(TemplateInstantiationNode)node.children[1])
        {


            builderStack.length++;
            node.children[1].accept(this);
            auto templateInstantiations = builderStack[$-1];
            builderStack.length--;
            auto instantiator = new TemplateInstantiator(records);
            curFuncCallSig = instantiator.instantiateFunction(
                curFuncCallSig, templateInstantiations
            );
            auto existsLookup = funcSigLookup(
                toplevelFuncs ~ importedFuncSigs, curFuncCallSig.funcName
            );
            if (!existsLookup.success)
            {
                toplevelFuncs ~= curFuncCallSig;
                // Add this instantiated, templated function to the end of the
                // abstract syntax tree, effectively bringing it into existence,
                // and allowing it to get typechecked later
                topNode.children ~= curFuncCallSig.funcDefNode;
            }
            auto newIdNode = new IdentifierNode();
            auto terminal = new ASTTerminal(
                curFuncCallSig.funcName, 0
            );
            newIdNode.children ~= terminal;
            node.children[0] = newIdNode;


            node.children[2].accept(this);
        }
        else
        {
            node.children[1].accept(this);
        }
    }

    void visit(DotAccessNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("DotAccessNode"));
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
        curType = normalize(curType, records);
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
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ name ~ " is not member of struct"
                );
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
            auto funcLookup = funcSigLookup(
                toplevelFuncs ~ importedFuncSigs, name
            );
            if (!funcLookup.success)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "No function[" ~ name ~ "]."
                );
            }
            curFuncCallSig = funcLookup.sig;
            node.children[1].accept(this);

            // TODO Finish this. Gotta actually determine whether the UFCS call
            // works

        }
    }

    void visit(IfStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("IfStmtNode"));
        funcScopes[$-1].syms.length++;
        // CondAssignmentsNode
        node.children[0].accept(this);
        // BoolExprNode or IsExprNode
        node.children[1].accept(this);
        auto boolType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (boolType.tag != TypeEnum.BOOL)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Non-bool expr in if statement expr."
            );
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
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ElseIfsNode"));
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(ElseIfStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ElseIfStmtNode"));
        funcScopes[$-1].syms.length++;
        // CondAssignmentsNode
        node.children[0].accept(this);
        // BoolExprNode or IsExprNode
        node.children[1].accept(this);
        auto boolType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (boolType.tag != TypeEnum.BOOL)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Non-bool expr in if statement expr."
            );
        }
        // BareBlockNode
        node.children[2].accept(this);
        funcScopes[$-1].syms.length--;
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
        funcScopes[$-1].syms.length++;
        // CondAssignmentsNode
        node.children[0].accept(this);
        // BoolExprNode
        node.children[1].accept(this);
        auto boolType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (boolType.tag != TypeEnum.BOOL)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Non-bool expr in while statement expr."
            );
        }
        // BareBlockNode
        node.children[2].accept(this);
        funcScopes[$-1].syms.length--;
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
        // ForeachArgsNode
        node.children[0].accept(this);
        // BoolExprNode
        node.children[1].accept(this);
        auto loopType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        Type*[] loopTypes;
        if (loopType.tag == TypeEnum.ARRAY || loopType.tag == TypeEnum.STRING)
        {
            loopTypes ~= loopType;
        }
        else if (loopType.tag == TypeEnum.TUPLE)
        {
            foreach (type; loopType.tuple.types)
            {
                if (type.tag != TypeEnum.ARRAY && type.tag != TypeEnum.STRING)
                {
                    throw new Exception(
                        errorHeader(node) ~ "\n"
                        ~ "Cannot loop over non-array/string types in loop "
                        ~ "tuple"
                    );
                }
                loopTypes ~= type;
            }
        }
        else
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Cannot loop over non-array types"
            );
        }
        if (foreachArgs.length != loopTypes.length
            && foreachArgs.length - 1 != loopTypes.length)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Foreach args must match loop types in number, plus optional "
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
            if (type.tag == TypeEnum.ARRAY)
            {
                pair.type = type.array.arrayType;
                this.stackVarAllocSize[curFuncName] += type.array
                                                           .arrayType
                                                           .size
                                                           .stackAlignSize;
            }
            else if (type.tag == TypeEnum.STRING)
            {
                auto charWrap = new Type();
                charWrap.tag = TypeEnum.CHAR;
                pair.type = charWrap;
                this.stackVarAllocSize[curFuncName] += charWrap.size
                                                               .stackAlignSize;
            }
            funcScopes[$-1].syms[$-1].decls[varName] = pair;
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
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ForeachArgsNode"));
        foreachArgs = [];
        foreach (child; node.children)
        {
            child.accept(this);
            foreachArgs ~= id;
        }
    }

    void visit(MatchStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("MatchStmtNode"));
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
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("MatchWhenNode"));
        // PatternNode
        node.children[0].accept(this);
        auto stmtIndex = 1;
        // Add scope for variable bindings in match expression and guard
        // clauses
        funcScopes[$-1].syms.length++;
        if (node.children.length > 1
            && cast(CondAssignmentsNode)node.children[1])
        {
            stmtIndex = 3;
            // CondAssignmentsNode
            node.children[1].accept(this);
            // BoolExprNode
            node.children[2].accept(this);
            auto boolType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (boolType.tag != TypeEnum.BOOL)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Non-bool expr in match guard clause expr."
                );
            }
        }
        // StatementNode
        node.children[stmtIndex].accept(this);
        funcScopes[$-1].syms.length--;
    }

    void visit(PatternNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("PatternNode"));
        node.children[0].accept(this);
    }

    void visit(DestructVariantPatternNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("DestructVariantPatternNode"));
        if (matchType.tag == TypeEnum.AGGREGATE)
        {
            matchType = instantiateAggregate(records, matchType.aggregate);
        }
        node.data["type"] = matchType;
        if (matchType.tag != TypeEnum.VARIANT)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Must match on " ~ matchType.tag.format
                ~ ", not variant type."
            );
        }
        auto matchTypeSave = matchType;
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
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Variant constructor does not exist"
            );
        }
        auto member = members[0];
        if (member.constructorElems.tag == TypeEnum.VOID)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Variant constructor [" ~ constructorName ~ "] of variant ["
                ~ matchType.variantDef.format ~ "]\nin `match` does not "
                ~ "contain any values to deconstruct"
            );
        }
        if (member.constructorElems.tuple.types.length
            != node.children[1..$].length)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Pattern sub-element quantity mismatch"
            );
        }
        foreach (child, subtype; lockstep(node.children[1..$],
                                          member.constructorElems.tuple.types))
        {
            matchType = subtype.normalize(records);
            child.accept(this);
        }
        matchType = matchTypeSave;
    }

    void visit(StructPatternNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("StructPatternNode"));
        node.data["type"] = matchType;
        if (matchType.tag != TypeEnum.STRUCT)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Must match on " ~ matchType.tag.format
                ~ ", not struct type."
            );
        }
        auto matchTypeSave = matchType;
        auto i = 0;
        // If the second node is an identifier node, then that means the first
        // node is the optional identifier node indicating the struct name,
        // which is purely sugar for the user, but we gotta verify it
        if (cast(IdentifierNode)node.children[1])
        {
            i = 1;
            node.children[0].accept(this);
            auto structName = id;
            if (matchType.structDef.name != structName)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Wrong optional struct name in match"
                );
            }
        }
        Type*[string] members;
        foreach (member; matchType.structDef.members)
        {
            members[member.name] = member.type;
        }
        bool[string] accessed;
        for (; i < node.children.length; i += 2)
        {
            node.children[i].accept(this);
            auto memberName = id;
            if (memberName !in members)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Struct deconstruction match with unknown member:\n"
                    ~ "  [" ~ memberName ~ "]\n"
                    ~ "  expecting member from struct: "
                    ~ matchTypeSave.structDef.format
                );
            }
            if (memberName in accessed)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Multiple match clauses for member\n"
                    ~ "  [" ~ memberName ~ "]\n"
                    ~ "  in struct: " ~ matchTypeSave.structDef.format
                );
            }
            accessed[memberName] = true;
            matchType = members[memberName];
            node.children[i+1].accept(this);
        }
        matchType = matchTypeSave;
    }

    void visit(BoolPatternNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("BoolPatternNode"));
        node.data["type"] = matchType;
        if (matchType.tag != TypeEnum.BOOL)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Must match on " ~ matchType.tag.format
                ~ ", not bool type."
            );
        }
    }

    void visit(StringPatternNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("StringPatternNode"));
        node.data["type"] = matchType;
        if (matchType.tag != TypeEnum.STRING)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Must match on " ~ matchType.tag.format
                ~ ", not string type."
            );
        }
    }

    void visit(CharPatternNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("CharPatternNode"));
        node.data["type"] = matchType;
        if (matchType.tag != TypeEnum.CHAR)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Must match on " ~ matchType.tag.format
                ~ ", not char type."
            );
        }
    }

    void visit(IntPatternNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("IntPatternNode"));
        node.data["type"] = matchType;
        if (!isIntegral(matchType))
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Must match on " ~ matchType.tag.format
                ~ ", not integer type."
            );
        }
    }

    void visit(FloatPatternNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("FloatPatternNode"));
        node.data["type"] = matchType;
        if (!isFloat(matchType))
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Must match on " ~ matchType.tag.format
                ~ ", not floating type."
            );
        }
    }

    void visit(TuplePatternNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("TuplePatternNode"));
        node.data["type"] = matchType;
        if (matchType.tag != TypeEnum.TUPLE)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Must match on " ~ matchType.tag.format
                ~ ", not tuple type."
            );
        }
        auto matchTypeSave = matchType;
        if (matchType.tuple.types.length != node.children.length)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Bad tuple match unpack: element quantity mismatch"
            );
        }
        foreach (child, subtype; lockstep(node.children,
                                          matchType.tuple.types))
        {
            matchType = subtype;
            child.accept(this);
        }
        matchType = matchTypeSave;
    }

    void visit(ArrayEmptyPatternNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ArrayPatternNode"));
        node.data["type"] = matchType;
        if (matchType.tag != TypeEnum.ARRAY)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Must match on " ~ matchType.tag.format
                ~ ", not array type."
            );
        }
    }

    void visit(ArrayPatternNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ArrayPatternNode"));
        node.data["type"] = matchType;
        if (matchType.tag != TypeEnum.ARRAY && matchType.tag != TypeEnum.STRING)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Must match on " ~ matchType.tag.format
                ~ ", not array or string type."
            );
        }
        auto matchTypeSave = matchType;
        auto endIndex = node.children.length;
        if (cast(IdentifierNode)node.children[$-1])
        {
            // Move back before the ".." token
            endIndex = endIndex - 2;
            node.children[$-1].accept(this);
            auto restName = id;
            auto pair = new VarTypePair();
            pair.varName = restName;
            pair.type = matchTypeSave;
            funcScopes[$-1].syms[$-1].decls[restName] = pair;
            this.stackVarAllocSize[curFuncName] += pair.type
                                                       .size
                                                       .stackAlignSize;
        }
        else if (cast(ASTTerminal)node.children[$-1])
        {
            // Move back before the ".." token
            endIndex = endIndex - 1;
        }
        if (matchType.tag == TypeEnum.ARRAY)
        {
            matchType = matchType.array.arrayType;
        }
        else if (matchType.tag == TypeEnum.STRING)
        {
            auto charType = new Type();
            charType.tag = TypeEnum.CHAR;
            matchType = charType;
        }
        foreach (child; node.children[0..endIndex])
        {
            child.accept(this);
        }
        matchType = matchTypeSave;
    }

    void visit(ArrayTailPatternNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ArrayTailPatternNode"));
        node.data["type"] = matchType;
        if (matchType.tag != TypeEnum.ARRAY && matchType.tag != TypeEnum.STRING)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Must match on " ~ matchType.tag.format
                ~ ", not array or string type."
            );
        }
        auto matchTypeSave = matchType;
        auto startIndex = 0;
        if (cast(IdentifierNode)node.children[0])
        {
            // Move past identifier node
            startIndex = startIndex + 1;
            node.children[0].accept(this);
            auto restName = id;
            auto pair = new VarTypePair();
            pair.varName = restName;
            pair.type = matchTypeSave;
            funcScopes[$-1].syms[$-1].decls[restName] = pair;
            this.stackVarAllocSize[curFuncName] += pair.type
                                                       .size
                                                       .stackAlignSize;
        }
        if (matchType.tag == TypeEnum.ARRAY)
        {
            matchType = matchType.array.arrayType;
        }
        else if (matchType.tag == TypeEnum.STRING)
        {
            auto charType = new Type();
            charType.tag = TypeEnum.CHAR;
            matchType = charType;
        }
        foreach (child; node.children[startIndex..$])
        {
            child.accept(this);
        }
        matchType = matchTypeSave;
    }

    void visit(WildcardPatternNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("WildcardPatternNode"));
    }

    void visit(VarOrBareVariantPatternNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("VarOrBareVariantPatternNode"));
        node.data["type"] = matchType;
        // IdentifierNode
        node.children[0].accept(this);
        auto var = id;
        auto maybeVariantDef = variantFromConstructor(records, var);
        if (maybeVariantDef !is null)
        {
            if (matchType.tag != TypeEnum.VARIANT)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Matched type is not variant type, but got constructor:\n"
                    ~ "  " ~ var ~ "\n"
                    ~ "  for variant: " ~ maybeVariantDef.format
                );
            }
            if (!matchType.variantDef.isMember(var))
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Constructor for wrong variant definition:\n"
                    ~ "  Expects: " ~ matchType.format ~ "\n"
                    ~ "  But got: " ~ maybeVariantDef.format
                );
            }
            auto member = matchType.variantDef.getMember(var);
            if (member.constructorElems.tag != TypeEnum.VOID)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Cannot have empty variant match on non-empty constructor"
                );
            }
        }
        // Is a variable binding
        else
        {
            auto pair = new VarTypePair();
            pair.varName = var;
            pair.type = matchType;
            funcScopes[$-1].syms[$-1].decls[var] = pair;
            this.stackVarAllocSize[curFuncName] += pair.type
                                                       .size
                                                       .stackAlignSize;
        }
    }

    // Note that we must cater to the whims of updating
    // this.stackVarAllocSize[curFuncName] with the stack sizes of each variable
    // declared in this expression
    void visit(IsExprNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("IsExprNode"));
        // BoolExprNode
        node.children[0].accept(this);
        auto exprType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        // IdentifierNode
        node.children[1].accept(this);
        auto constructorName = id;
        auto variantDef = variantFromConstructor(records, constructorName);
        if (exprType.tag != TypeEnum.VARIANT)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Left side of `is` expression must be a variant type"
            );
        }
        if (variantDef !is null)
        {
            if (!exprType.variantDef.isMember(constructorName))
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Right side of `is` expression must be a valid "
                    "constructor for the left side variant type"
                );
            }
            auto member = exprType.variantDef
                                  .getMember(constructorName);
            if (member.constructorElems.tag == TypeEnum.VOID
                && node.children[2..$].length > 0)
            {
                throw new Exception(
                    errorHeader(node) ~ "\n"
                    ~ "Cannot bind variables in empty constructor"
                );
            }
            if (member.constructorElems.tag != TypeEnum.VOID)
            {
                if (member.constructorElems.tuple.types.length
                    != node.children[2..$].length)
                {
                    throw new Exception(
                        errorHeader(node) ~ "\n"
                        ~ "Pattern sub-element quantity mismatch"
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
                        pair.type = subtype.normalize(records);
                        stackVarAllocSize[curFuncName]
                            += subtype.size
                                      .stackAlignSize;
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
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Variant constructor " ~ constructorName ~ " does not exist"
            );
        }
        node.data["type"] = exprType;
        node.data["constructor"] = constructorName;
    }

    void visit(VariantIsMatchNode node) {}
    void visit(IdOrWildcardNode node) {}

    // Note that in the syntax BoolExpr <-= BoolExpr, the left expression must
    // yield a chan-type that contains the same type as the type of the right
    // expression
    void visit(ChanWriteNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ChanWriteNode"));
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
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Can't chan-write to non-channel"
            );
        }
        else if (!leftType.chan.chanType.cmp(rightType))
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Can't chan-write mismatched types"
            );
        }
    }

    void visit(ChanReadNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("ChanReadNode"));
        node.children[0].accept(this);
        auto type = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (type.tag != TypeEnum.CHAN)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Cannot chan-read from non-channel"
            );
        }
        builderStack[$-1] ~= type.chan.chanType.copy;
        node.data["type"] = type.chan.chanType.copy;
    }

    void visit(SpawnStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("SpawnStmtNode"));
        node.children[0].accept(this);
        auto name = id;
        auto funcLookup = funcSigLookup(
            toplevelFuncs ~ importedFuncSigs, name
        );
        if (!funcLookup.success)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "No function " ~ name ~ " to spawn"
            );
        }
        if (funcLookup.sig.returnType.tag != TypeEnum.VOID)
        {
            throw new Exception(
                errorHeader(node) ~ "\n"
                ~ "Cannot spawn non-void function"
            );
        }
        curFuncCallSig = funcLookup.sig;
        node.data["sig"] = funcLookup.sig;
        node.children[1].accept(this);
    }

    void visit(YieldStmtNode node)
    {
        debug (FUNCTION_TYPECHECK_TRACE) mixin(tracer("YieldStmtNode"));
    }

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
    void visit(ImportStmtNode node) {}
    void visit(ImportLitNode node) {}
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
