import std.stdio;
import Function;
import typedecl;
import parser;
import visitor;
import std.conv;
import std.algorithm;
import std.array;
import std.range;
import ExprCodeGenerator;

// Since functions can return tuples, the function ABI is to place the return
// value into an assumed-allocated location just before where the arguments are
// placed. Note that arguments 0-5 are in registers rdi, rsi, rdx, rcx, r8, and
// r9. So, on the stack for a function call, we have:
// return value allocation
// arg8
// arg7
// arg6
// return address
// RBP
// beginning of available stack space

// The 64-bit ABI additionally guarantees 128 bytes of space below RSP that can
// be freely used by the function definition. Any sub's from RSP will continue
// to move this 128 byte space further downward. This space can only be
// considered "available" if this function call is a leaf call in the call tree.
// Otherwise, it'll get clobbered by a deeper function call. So if the call
// isn't a leaf call, stack space must be specifically allocated by sub's from
// RSP. The stack must be kept on a 16 byte alignment or else everything blows
// up

// Any operation that expects an expression value can be found on the top of the
// stack, save for the actual variable values, which are in register r8, or
// across r8 and r9 in the case of a fat ptr. A tuple will always be on the
// stack

const RBP_SIZE = 8;
const RETURN_ADDRESS_SIZE = 8;
const STACK_PROLOGUE_SIZE = RBP_SIZE + RETURN_ADDRESS_SIZE;
const ENVIRON_PTR_SIZE = 8;

const CLAM_PTR_SIZE = 8; // sizeof(char*))
const REF_COUNT_SIZE = 4; // sizeof(uint32_t))
const CLAM_STR_SIZE = 4; // sizeof(uint32_t))
const STR_START_OFFSET = REF_COUNT_SIZE + CLAM_STR_SIZE;
const VARIANT_TAG_SIZE = 4; // sizeof(uint32_t))

const INT_REG = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"];
const FLOAT_REG = ["xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6",
                   "xmm7"];

debug (COMPILE_TRACE)
{
    string traceIndent;
    enum tracer =
        `
        string mixin_funcName = __FUNCTION__;
        writeln(traceIndent, "Entered: ", mixin_funcName);
        traceIndent ~= "  ";
        scope(success)
        {
            traceIndent = traceIndent[0..$-2];
            writeln(traceIndent, "Exiting: ", mixin_funcName);
        }
        `;
}

auto getIdentifier(IdentifierNode node)
{
    return (cast(ASTTerminal)node.children[0]).token;
}

auto getOffset(VarTypePair*[] vars, ulong index)
{
    return getAlignedIndexOffset(vars.map!(a => a.type.size).array, index);
}

auto getWordSize(ulong size)
{
    final switch (size)
    {
    case 1:  return "byte";
    case 2:  return "word";
    case 4:  return "dword";
    case 8:  return "qword";
    case 16: return "oword";
    }
}

auto getRRegSuffix(ulong size)
{
    final switch (size)
    {
    case 1: return "b";
    case 2: return "w";
    case 4: return "d";
    case 8: return "";
    }
}

// Get the power-of-2 size larger than the input size, for use in array size
// allocations. Arrays are always a power-of-2 in size.
// Credit: Henry S. Warren, Jr.'s "Hacker's Delight.", and Larry Gritz from
// http://stackoverflow.com/questions/364985/algorithm-for-finding-the-smallest-power-of-two-thats-greater-or-equal-to-a-giv
auto getAllocSize(ulong requestedSize)
{
    auto x = requestedSize;
    if (x < 0)
    {
        return 0;
    }
    --x;
    x |= x >> 1;
    x |= x >> 2;
    x |= x >> 4;
    x |= x >> 8;
    x |= x >> 16;
    x |= x >> 32;
    return x+1;
}

unittest
{
    assert(0.getAllocSize == 0);
    assert(1.getAllocSize == 1);
    assert(2.getAllocSize == 2);
    assert(3.getAllocSize == 4);
    assert(4.getAllocSize == 4);
    assert(6.getAllocSize == 8);
    assert(1002.getAllocSize == 1024);
}

auto toNasmDataString(string input)
{
    auto str = "`";
    //foreach (c; input)
    //{
    //    switch (c)
    //    {
    //    case ' ': .. case '~': str ~= c;
    //    }
    //}
    str ~= input;
    str ~= "`, 0";
    return str;
}

struct DataEntry
{
    string label;
    string data;

    static auto toNasmDataString(string input)
    {
        auto str = "`";
        //foreach (c; input)
        //{
        //    switch (c)
        //    {
        //    case ' ': .. case '~': str ~= c;
        //    }
        //}
        str ~= input;
        str ~= "`, 0";
        return str;
    }
}

struct FloatEntry
{
    string label;
    string floatStr;
}

struct Context
{
    DataEntry*[] dataEntries;
    FloatEntry*[] floatEntries;
    string[] blockEndLabels;
    string[] blockNextLabels;
    FuncSig*[string] externFuncs;
    FuncSig*[string] compileFuncs;
    StructType*[string] structDefs;
    VariantType*[string] variantDefs;
    VarTypePair*[] closureVars;
    VarTypePair*[] funcArgs;
    VarTypePair*[] stackVars;
    Type* retType;
    // Set when calculating l-value addresses, to determine how the assignment
    // should be made
    bool isStackAligned;
    private uint topOfStack;
    private uint uniqLabelCounter;
    private uint uniqDataCounter;

    auto getUniqDataLabel()
    {
        return "__S" ~ (uniqDataCounter++).to!string;
    }

    auto getUniqLabel()
    {
        return ".L" ~ (uniqLabelCounter++).to!string;
    }

    void refreshLabelCounter()
    {
        uniqLabelCounter = 0;
    }

    auto getTop()
    {
        return (stackVars.length * 8) + topOfStack;
    }

    void allocateStackSpace(uint bytes)
    {
        topOfStack += bytes;
    }

    void deallocateStackSpace(uint bytes)
    {
        topOfStack -= bytes;
    }

    void resetStack()
    {
        topOfStack = 0;
    }

    bool isStackAlignedVar(string varName)
    {
        foreach (var; stackVars)
        {
            if (var.varName == varName)
            {
                return true;
            }
        }
        foreach (var; funcArgs)
        {
            if (var.varName == varName)
            {
                return true;
            }
        }
        return false;
    }

    // Either the value of the variable is in r8, implying that the type is
    // either 1, 2, 4, or 8 bytes, or it is split between r8 and r9, where
    // r8 is the environment portion of a fat pointer, and r9 is the function
    // pointer itself. Because we've passed the typecheck stage, we're
    // guaranteed that lookup will succeed
    string compileVarGet(string varName)
    {
        const environOffset = (closureVars.length > 0)
                           ? ENVIRON_PTR_SIZE
                           : 0;
        const retValOffset = retType.size;
        foreach (i, var; funcArgs)
        {
            if (varName == var.varName)
            {
                if (var.type.size <= 8)
                {
                    return "    mov    r8, qword [rbp+"
                        ~ (STACK_PROLOGUE_SIZE + environOffset + retValOffset +
                           getOffset(funcArgs, i)).to!string ~ "]\n";
                }
                return "    mov    r8, qword [rbp+"
                    ~ (STACK_PROLOGUE_SIZE + environOffset + retValOffset +
                       getOffset(funcArgs, i)).to!string ~ "]\n"
                    ~ "    mov    r9, qword [rbp+"
                    ~ (STACK_PROLOGUE_SIZE + environOffset + retValOffset +
                       getOffset(funcArgs, i) + 8).to!string ~ "]\n";
            }
        }
        foreach (i, var; closureVars)
        {
            if (varName == var.varName)
            {
                auto str = "    mov    r10, [rbp+8]\n";
                if (var.type.size <= 8)
                {
                    str ~= "    mov    r8, qword [r10+"
                        ~ getOffset(closureVars, i).to!string ~ "]\n";
                    return str;
                }
                str ~= "    mov    r8, qword [r10+"
                    ~ getOffset(funcArgs, i).to!string ~ "]\n"
                    ~ "    mov    r9, qword [r10+"
                    ~ getOffset(funcArgs, i).to!string ~ "]\n";
                return str;
            }
        }
        foreach (i, var; stackVars)
        {
            if (varName == var.varName)
            {
                if (var.type.size <= 8)
                {
                    return "    mov    r8, qword [rbp-"
                        ~ ((i + 1) * 8).to!string ~ "]\n";
                }
                return "    mov    r8, qword [rbp-"
                    ~ ((i + 1) * 8).to!string ~ "]\n"
                    ~ "    mov    r9, qword [rbp-"
                    ~ ((i + 1) * 8 + 8).to!string ~ "]\n";
            }
        }
        assert(false);
        return "";
    }

    string compileVarAddress(string varName)
    {
        const environOffset = (closureVars.length > 0)
                           ? ENVIRON_PTR_SIZE
                           : 0;
        const retValOffset = retType.size;
        foreach (i, var; funcArgs)
        {
            if (varName == var.varName)
            {
                if (var.type.size <= 8)
                {
                    return "    mov    r8, rbp\n"
                         ~ "    add    r8, "
                         ~ (STACK_PROLOGUE_SIZE
                            + environOffset
                            + retValOffset
                            + getOffset(funcArgs, i)).to!string
                         ~ "\n";
                }
                return "    mov    r8, rbp\n"
                     ~ "    add    r8, "
                     ~ (STACK_PROLOGUE_SIZE
                        + environOffset
                        + retValOffset
                        + getOffset(funcArgs, i)).to!string
                     ~ "\n"
                     ~ "    mov    r9, rbp\n"
                     ~ "    add    r9, "
                     ~ (STACK_PROLOGUE_SIZE
                        + environOffset
                        + retValOffset
                        + getOffset(funcArgs, i) + 8).to!string
                     ~ "\n";
            }
        }
        foreach (i, var; closureVars)
        {
            if (varName == var.varName)
            {
                auto str = "    mov    r10, [rbp+8]\n";
                if (var.type.size <= 8)
                {
                    str ~= "    mov    r8, r10\n";
                    str ~= "    add    r8, "
                        ~ getOffset(closureVars, i).to!string ~ "\n";
                    return str;
                }
                str ~= "    mov    r8, r10\n";
                str ~= "    add    r8, " ~ getOffset(funcArgs, i).to!string
                                         ~ "\n";
                str ~= "    mov    r9, r10\n";
                str ~= "    add    r9, " ~ getOffset(funcArgs, i).to!string
                                         ~ "\n";
                return str;
            }
        }
        foreach (i, var; stackVars)
        {
            if (varName == var.varName)
            {
                if (var.type.size <= 8)
                {
                    return "    mov    r8, rbp\n"
                         ~ "    sub    r8, " ~ ((i + 1) * 8).to!string ~ "\n";
                }
                return "    mov    r8, rbp\n"
                     ~ "    sub    r8, " ~ ((i + 1) * 8).to!string ~ "\n"
                     ~ "    mov    r9, rbp\n"
                     ~ "    sub    r9, " ~ ((i + 1) * 8 + 8).to!string ~ "]n";
            }
        }
        assert(false);
        return "";
    }

    // We assume that the value we're setting is either in r8, when the type is
    // 1, 2, 4, or 8 bytes, or it is split across r8 and r9 in the case of a fat
    // pointer. We then store the value back into its allocated memory location
    string compileVarSet(string varName)
    {
        "enter".writeln;
        scope (success) "leave".writeln;
        const environOffset = (closureVars.length > 0)
                           ? ENVIRON_PTR_SIZE
                           : 0;
        "ret type check?".writeln;
        const retValOffset = retType.size;
        "yup".writeln;
        foreach (i, var; funcArgs)
        {
            if (varName == var.varName)
            {
                if (var.type.size <= 8)
                {
                    return "    mov    qword [rbp+"
                        ~ (STACK_PROLOGUE_SIZE + environOffset + retValOffset +
                           getOffset(funcArgs, i)).to!string ~ "], r8\n";
                }
                return "    mov    qword [rbp+"
                    ~ (STACK_PROLOGUE_SIZE + environOffset + retValOffset +
                       getOffset(funcArgs, i)).to!string ~ "], r8\n"
                    ~ "    mov    qword [rbp+"
                    ~ (STACK_PROLOGUE_SIZE + environOffset + retValOffset +
                       getOffset(funcArgs, i) + 8).to!string ~ "], r9\n";
            }
        }
        foreach (i, var; closureVars)
        {
            if (varName == var.varName)
            {
                auto str = "    mov    r10, [rbp+" ~ 8.to!string ~ "]\n";
                if (var.type.size <= 8)
                {
                    str ~= "    mov    qword [r10+"
                        ~ getOffset(closureVars, i).to!string ~ "], r8\n";
                    return str;
                }
                str ~= "    mov    qword [r10+"
                    ~ getOffset(funcArgs, i).to!string ~ "], r8\n"
                    ~ "    mov    qword [r10+"
                    ~ getOffset(funcArgs, i).to!string ~ "], r9\n";
                return str;
            }
        }
        foreach (i, var; stackVars)
        {
            if (varName == var.varName)
            {
                "just before size check".writeln;
                if (var.type.size <= 8)
                {
                    return "    mov    qword [rbp-"
                        ~ ((i + 1) * 8).to!string ~ "], r8\n";
                }
                return "    mov    qword [rbp-"
                    ~ ((i + 1) * 8).to!string ~ "], r8\n"
                    ~ "    mov    qword [rbp-"
                    ~ ((i + 1) * 8 + 8).to!string ~ "], r9\n";
            }
        }
        assert(false);
        return "";
    }
}

string compileFunction(FuncSig* sig, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto func = "";
    func ~= sig.funcName ~ ":\n";
    func ~= "    push   rbp         ; set up stack frame\n";
    func ~= "    mov    rbp, rsp\n";

    // TODO the following is temporary until a we have a function analyzer that
    // tells us the maximum amount of stack space a function will allocate.
    // Which will also be super important for once green threads are implemented

    func ~= "    sub    rsp, 128    ; dirty dirty hack\n";
    vars.closureVars = sig.closureVars;
    auto intRegIndex = 0;
    auto floatRegIndex = 0;
    vars.funcArgs = [];
    vars.stackVars = [];
    vars.resetStack();
    foreach (arg; sig.funcArgs)
    {
        if (arg.type.isFloat)
        {
            if (floatRegIndex >= FLOAT_REG.length)
            {
                vars.funcArgs ~= arg;
            }
            else
            {
                vars.stackVars ~= arg;
                func ~= "    movsd  qword [rbp-" ~ vars.getTop.to!string
                                                 ~ "], "
                                                 ~ FLOAT_REG[floatRegIndex]
                                                 ~ "\n";
                floatRegIndex++;
            }
        }
        else
        {
            if (intRegIndex >= INT_REG.length)
            {
                vars.funcArgs ~= arg;
            }
            else
            {
                vars.stackVars ~= arg;
                vars.getTop.writeln();
                func ~= "    mov    qword [rbp-" ~ vars.getTop.to!string
                                                 ~ "], "
                                                 ~ INT_REG[intRegIndex] ~ "\n";
                intRegIndex++;
            }
        }
    }
    vars.retType = sig.returnType;
    vars.refreshLabelCounter();
    sig.funcBodyBlocks.writeln;
    func ~= compileBlock(
        cast(BareBlockNode)sig.funcBodyBlocks.children[0], vars
    );
    func ~= "    add    rsp, 128    ; dirty dirty hack\n";
    func ~= "    mov    rsp, rbp    ; takedown stack frame\n";
    func ~= "    pop    rbp\n";
    func ~= "    ret\n";
    return func;
}

string compileBlock(BareBlockNode block, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto code = "";
    foreach (statement; block.children)
    {
        code ~= compileStatement(cast(StatementNode)statement, vars);
    }
    return code;
}

string compileStatement(StatementNode statement, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto child = statement.children[0];
    if (cast(BareBlockNode)child)
        return compileBlock(cast(BareBlockNode)child, vars);
    else if (cast(ReturnStmtNode)child)
        return compileReturn(cast(ReturnStmtNode)child, vars);
    else if (cast(IfStmtNode)child)
        return compileIfStmt(cast(IfStmtNode)child, vars);
    else if (cast(WhileStmtNode)child)
        return compileWhileStmt(cast(WhileStmtNode)child, vars);
    else if (cast(ForStmtNode)child)
        return compileForStmt(cast(ForStmtNode)child, vars);
    else if (cast(ForeachStmtNode)child)
        return compileForeachStmt(cast(ForeachStmtNode)child, vars);
    else if (cast(MatchStmtNode)child)
        return compileMatchStmt(cast(MatchStmtNode)child, vars);
    else if (cast(DeclarationNode)child)
        return compileDeclaration(cast(DeclarationNode)child, vars);
    else if (cast(AssignExistingNode)child)
        return compileAssignExisting(cast(AssignExistingNode)child, vars);
    else if (cast(SpawnStmtNode)child)
        return compileSpawnStmt(cast(SpawnStmtNode)child, vars);
    else if (cast(YieldStmtNode)child)
        return compileYieldStmt(cast(YieldStmtNode)child, vars);
    else if (cast(ChanWriteNode)child)
        return compileChanWrite(cast(ChanWriteNode)child, vars);
    else if (cast(FuncCallNode)child)
        return compileFuncCall(cast(FuncCallNode)child, vars);
    assert(false);
    return "";
}

string compileReturn(ReturnStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    if (node.children.length == 0)
    {
       return "    mov    rsp, rbp    ; takedown stack frame\n"
              "    pop    rbp\n"
              "    ret\n";
    }
    const environOffset = (vars.closureVars.length > 0)
                        ? ENVIRON_PTR_SIZE
                        : 0;
    auto str = "";
    str ~= compileExpression(cast(BoolExprNode)node.children[0], vars);
    if (vars.retType.size <= 8)
    {

    }
    // Handle the fat ptr case
    else if (vars.retType.size == 16)
    {

    }
    // Handle the tuple case
    else
    {

    }
    str ~= "mov    rsp, rbp    ; takedown stack frame\n"
           "pop    rbp\n"
           "ret\n";
    return str;
}

string compileIfStmt(IfStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    str ~= compileCondAssignments(
        cast(CondAssignmentsNode)node.children[0], vars
    );
    if (cast(IsExprNode)node.children[1])
    {
        str ~= compileIsExpr(cast(IsExprNode)node.children[1], vars);
    }
    else
    {
        str ~= compileBoolExpr(cast(BoolExprNode)node.children[1], vars);
    }
    auto blockEndLabel = vars.getUniqLabel();
    auto blockNextLabel = vars.getUniqLabel();
    vars.blockEndLabels ~= blockEndLabel;
    str ~= "    cmp    r8, 0\n";
    // If it's zero, then it's false, meaning go to the next label
    str ~= "    je     " ~ blockNextLabel ~ "\n";
    str ~= compileBlock(cast(BareBlockNode)node.children[2], vars);
    str ~= "    jmp    " ~ blockEndLabel ~ "\n";
    str ~= blockNextLabel ~ ":\n";
    str ~= compileElseIfs(cast(ElseIfsNode)node.children[3], vars);
    str ~= compileElseStmt(cast(ElseStmtNode)node.children[4], vars);
    str ~= blockEndLabel ~ ":\n";
    vars.blockEndLabels.length--;
    return str;
}

string compileElseIfs(ElseIfsNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    foreach (child; node.children)
    {
        str ~= compileElseIfStmt(cast(ElseIfStmtNode)child, vars);
    }
    return str;
}

string compileElseIfStmt(ElseIfStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    str ~= compileCondAssignments(
        cast(CondAssignmentsNode)node.children[0], vars
    );
    if (cast(IsExprNode)node.children[1])
    {
        str ~= compileIsExpr(cast(IsExprNode)node.children[1], vars);
    }
    else
    {
        str ~= compileBoolExpr(cast(BoolExprNode)node.children[1], vars);
    }
    auto blockNextLabel = vars.getUniqLabel();
    str ~= "    cmp    r8, 0\n";
    // If it's zero, then it's false, meaning go to the next label
    str ~= "    je     " ~ blockNextLabel ~ "\n";
    str ~= compileBlock(cast(BareBlockNode)node.children[2], vars);
    str ~= "    jmp    " ~ vars.blockEndLabels[$-1] ~ "\n";
    str ~= blockNextLabel ~ ":\n";
    return str;
}

string compileElseStmt(ElseStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    if (node.children.length > 0)
    {
        str ~= compileBlock(cast(BareBlockNode)node.children[0], vars);
    }
    return str;
}

string compileWhileStmt(WhileStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto blockLoopLabel = vars.getUniqLabel();
    auto blockEndLabel = vars.getUniqLabel();
    auto str = "";
    str ~= compileCondAssignments(
        cast(CondAssignmentsNode)node.children[0], vars
    );
    str ~= blockLoopLabel ~ ":\n";
    if (cast(IsExprNode)node.children[1])
    {
        str ~= compileIsExpr(cast(IsExprNode)node.children[1], vars);
    }
    else
    {
        str ~= compileBoolExpr(cast(BoolExprNode)node.children[1], vars);
    }
    str ~= "    cmp    r8, 0\n";
    // If it's zero, then it's false, meaning don't enter the loop
    str ~= "    je     " ~ blockEndLabel ~ "\n";
    str ~= compileBlock(cast(BareBlockNode)node.children[2], vars);
    str ~= "    jmp    " ~ blockLoopLabel ~ "\n";
    str ~= blockEndLabel ~ ":\n";
    return str;
}

string compileForStmt(ForStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileForeachStmt(ForeachStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileMatchStmt(MatchStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileDeclaration(DeclarationNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto child = node.children[0];
    if (cast(DeclTypeInferNode)child) {
        return compileDeclTypeInfer(cast(DeclTypeInferNode)child, vars);
    }
    else if (cast(DeclAssignmentNode)child) {
        return compileDeclAssignment(cast(DeclAssignmentNode)child, vars);
    }
    else if (cast(VariableTypePairNode)child) {
        return compileVariableTypePair(cast(VariableTypePairNode)child, vars);
    }
    return "";
}

string compileDeclTypeInfer(DeclTypeInferNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto left = node.children[0];
    auto str = compileExpression(cast(BoolExprNode)node.children[1], vars);
    auto type = node.children[1].data["type"].get!(Type*);
    if (cast(IdentifierNode)left)
    {
        auto varName = getIdentifier(cast(IdentifierNode)left);
        auto var = new VarTypePair;
        var.varName = varName;
        var.type = type;
        vars.stackVars ~= var;
        str = "    ; var infer assign [" ~ varName
                                         ~ "]\n"
                                         ~ str
                                         ~ vars.compileVarSet(varName);
    }
    else
    {

    }
    return str;
}

string compileVariableTypePair(VariableTypePairNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileAssignExisting(AssignExistingNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    auto op = (cast(ASTTerminal)node.children[1]).token;
    auto type = node.children[2].data["type"].get!(Type*);
    str ~= compileBoolExpr(cast(BoolExprNode)node.children[2], vars);
    vars.allocateStackSpace(8);
    auto valLoc = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ valLoc ~ "], r8\n";
    // Assume it's true to begin with
    vars.isStackAligned = true;
    str ~= compileLorRValue(cast(LorRValueNode)node.children[0], vars);
    str ~= "    mov    r9, qword [rbp-" ~ valLoc ~ "]\n";
    vars.deallocateStackSpace(8);
    if (vars.isStackAligned)
    {
        str ~= "    mov    qword [r8], r9\n";
    }
    else
    {
        str ~= "    mov    " ~ getWordSize(type.size)
                             ~ " [r8], r9"
                             ~ getRRegSuffix(type.size) ~ "\n";
    }
    return str;
}

string compileLorRValue(LorRValueNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    auto id = getIdentifier(cast(IdentifierNode)node.children[0]);
    str ~= vars.compileVarAddress(id);
    if (node.children.length > 1)
    {
        str ~= compileLorRTrailer(cast(LorRTrailerNode)node.children[1], vars);
        vars.isStackAligned = false;
    }
    // This check is hit when we're either checking the top-level LoRValue id,
    // or when it's a struct member. A struct member may be the same id as
    // a stack variable, so we can tell that we're referring to a stack
    // variable if isStackAligned is still set to the default true value from
    // compileAssignExisting()
    else if (vars.isStackAligned && !vars.isStackAlignedVar(id))
    {
        vars.isStackAligned = false;
    }
    return str;
}

string compileLorRTrailer(LorRTrailerNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    vars.allocateStackSpace(8);
    auto valLoc = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ valLoc ~ "], r8\n";
    auto child = node.children[0];
    if (cast(IdentifierNode)child) {
        assert(false, "Unimplemented");
    }
    else if (cast(SingleIndexNode)child) {
        str ~= compileSingleIndex(cast(SingleIndexNode)child, vars);
        str ~= "    mov    r9, qword [rbp-" ~ valLoc ~ "]\n";
        // [r9] is the actual variable we're indexing, so
        // [r9]+(header offset + r8 * type.size) is the address we want. But we
        // need to know type.size, so we're probably gonna need to change
        // Function.d, not only to get the type, but also because the grammar
        // changes need to be updated in the typechecker anyway
        str ~= "    ";
    }
    vars.deallocateStackSpace(8);
    return str;
}

string compileCondAssignments(CondAssignmentsNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    foreach (child; node.children)
    {
        str ~= compileCondAssign(cast(CondAssignNode)child, vars);
    }
    return str;
}

string compileCondAssign(CondAssignNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return compileAssignment(cast(AssignmentNode)node.children[0], vars);
}

string compileAssignment(AssignmentNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    auto child = node.children[0];
    if (cast(DeclTypeInferNode)child) {
        str ~= compileDeclTypeInfer(cast(DeclTypeInferNode)child, vars);
    }
    else if (cast(AssignExistingNode)child) {
        str ~= compileAssignExisting(cast(AssignExistingNode)child, vars);
    }
    else if (cast(DeclAssignmentNode)child) {
        str ~= compileDeclAssignment(cast(DeclAssignmentNode)child, vars);
    }
    return str;
}

string compileDeclAssignment(DeclAssignmentNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    return str;
}

string compileSpawnStmt(SpawnStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileYieldStmt(YieldStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileChanWrite(ChanWriteNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileFuncCall(FuncCallNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto funcName = getIdentifier(cast(IdentifierNode)node.children[0]);
    auto str = compileArgList(cast(FuncCallArgListNode)node.children[1], vars);
    auto numArgs = (cast(ASTNonTerminal)node.children[1]).children.length;
    str ~= "    call   " ~ funcName ~ "\n";
    if (numArgs > 6)
    {
        str ~= "    add    rsp, " ~ ((numArgs - 6) * 8).to!string ~ "\n";
    }
    return str;
}

string compileArgList(FuncCallArgListNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);

    // If there are more than 6 args, then after we pop off the top 48 bytes,
    // the remaining arguments are on the top of the stack.

    // TODO Might need to ensure things are in the right order, and might need
    // to handle fat ptrs in a special way

    // TODO The space for the return value should be just before the arguments,
    // not just after, so that I can clear the stack of the arguments, and in
    // the case of an extern func, I can just populate the empty space with the
    // value in RAX

    auto str = "";
    TypeEnum[] types;
    foreach_reverse (child; node.children)
    {
        str ~= compileExpression(child, vars);
        auto type = child.data["type"].get!(Type*).tag;
        types ~= type;
        switch (type)
        {
        case TypeEnum.FUNCPTR:
            assert(false, "unimplemented");
            vars.allocateStackSpace(8);
            str ~= "    mov    qword [rbp-" ~ vars.getTop.to!string ~ "], "
                                            ~ "r8\n";
            vars.allocateStackSpace(8);
            str ~= "    mov    qword [rbp-" ~ vars.getTop.to!string ~ "], "
                                            ~ "r9\n";
            break;
        case TypeEnum.DOUBLE:
            vars.allocateStackSpace(8);
            str ~= "    movsd  qword [rbp-" ~ vars.getTop.to!string ~ "], "
                                            ~ "xmm0\n";
            break;
        case TypeEnum.FLOAT:
            vars.allocateStackSpace(8);
            str ~= "    cvtss2sd xmm0, xmm0\n";
            str ~= "    movsd  qword [rbp-" ~ vars.getTop.to!string ~ "], "
                                            ~ "xmm0\n";
            break;
        default:
            vars.allocateStackSpace(8);
            str ~= "    mov    qword [rbp-" ~ vars.getTop.to!string ~ "], "
                                            ~ "r8\n";
            break;
        }
    }


    // TODO need to ensure that all func call registers are properly populated.
    // This will involve keeping track of the types of the things taken off the
    // stack, so that the correct corresponding rxx or xmmx register is
    // populated, and to ensure that any remaining arguments are left on the
    // stack


    auto intRegIndex = 0;
    auto floatRegIndex = 0;
    auto numArgs = node.children.length;
    foreach (i; 0..numArgs)
    {
        switch (types[$ - 1 - i])
        {
        case TypeEnum.FUNCPTR:
            assert(false, "unimplemented");
            break;
        case TypeEnum.FLOAT:
        case TypeEnum.DOUBLE:
            if (floatRegIndex < FLOAT_REG.length)
            {
                str ~= "    movsd  " ~ FLOAT_REG[floatRegIndex]
                                     ~ ", qword [rbp-"
                                     ~ vars.getTop.to!string
                                     ~ "]\n";
                vars.deallocateStackSpace(8);
                floatRegIndex++;
            }
            else
            {
                // TODO handle the case where we've run out of float registers
                // and need this argument to remain on the stack
            }
            break;
        default:
            if (intRegIndex < INT_REG.length)
            {
                str ~= "    mov    " ~ INT_REG[intRegIndex]
                                     ~ ", qword [rbp-"
                                     ~ vars.getTop.to!string
                                     ~ "]\n";
                vars.deallocateStackSpace(8);
                intRegIndex++;
            }
            else
            {
                // TODO handle the case where we've run out of int registers
                // and need this argument to remain on the stack
            }
            break;
        }
    }
    return str;
}
