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

auto getStackOffset(VarTypePair*[] vars, ulong index)
{
    return getAlignedSize(vars[0..index].map!(a => a.type.size).array);
}

auto getWordSize(Type* type)
{
    final switch (type.size)
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
    FuncSig*[string] externFuncs;
    FuncSig*[string] compileFuncs;
    VarTypePair*[] closureVars;
    VarTypePair*[] funcArgs;
    VarTypePair*[] stackVars;
    Type* retType;
    ulong[] tempBytes;
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

    auto getStackPtrOffset()
    {
        return tempBytes.reduce!((a, b) => a + b)
            + getStackOffset(stackVars, stackVars.length);
    }

    auto allocateTempSpace(ulong size)
    {
        tempBytes ~= getPadding(cast(int)getStackPtrOffset(), cast(int)size)
            + size;
    }

    auto deallocateTempSpace()
    {
        tempBytes = tempBytes[0..$-1];
    }

    auto getTopTempSize()
    {
        return tempBytes[$-1];
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
                    return "    mov    r8, " ~ getWordSize(var.type) ~ " [rbp+"
                        ~ (STACK_PROLOGUE_SIZE + environOffset + retValOffset +
                           getOffset(funcArgs, i)).to!string ~ "]\n";
                }
                return "    mov    r8, QWORD [rbp+"
                    ~ (STACK_PROLOGUE_SIZE + environOffset + retValOffset +
                       getOffset(funcArgs, i)).to!string ~ "]\n"
                    ~ "    mov    r9, QWORD [rbp+"
                    ~ (STACK_PROLOGUE_SIZE + environOffset + retValOffset +
                       getOffset(funcArgs, i) + 8).to!string ~ "]\n";
            }
        }
        foreach (i, var; closureVars)
        {
            if (varName == var.varName)
            {
                auto str = "    mov    r10, [rbp+" ~ 8.to!string ~ "]\n";
                if (var.type.size <= 8)
                {
                    str ~= "    mov    r8, " ~ getWordSize(var.type) ~ " [r10+"
                        ~ getOffset(closureVars, i).to!string ~ "]\n";
                    return str;
                }
                str ~= "    mov    r8, QWORD [r10+"
                    ~ getOffset(funcArgs, i).to!string ~ "]\n"
                    ~ "    mov    r9, QWORD [r10+"
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
                    return "    mov    r8, " ~ getWordSize(var.type) ~ " [rbp-"
                        ~ (getStackOffset(stackVars, i)).to!string ~ "]\n";
                }
                return "    mov    r8, QWORD [rbp-"
                    ~ (getStackOffset(stackVars, i)).to!string ~ "]\n"
                    ~ "    mov    r9, QWORD [rbp-"
                    ~ (getStackOffset(stackVars, i) + 8).to!string ~ "]\n";
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
                    return "    mov    " ~ getWordSize(var.type) ~ " [rbp+"
                        ~ (STACK_PROLOGUE_SIZE + environOffset + retValOffset +
                           getOffset(funcArgs, i)).to!string ~ "], r8\n";
                }
                return "    mov    QWORD [rbp+"
                    ~ (STACK_PROLOGUE_SIZE + environOffset + retValOffset +
                       getOffset(funcArgs, i)).to!string ~ "], r8\n"
                    ~ "    mov    QWORD [rbp+"
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
                    str ~= "    mov    " ~ getWordSize(var.type) ~ " [r10+"
                        ~ getOffset(closureVars, i).to!string ~ "], r8\n";
                    return str;
                }
                str ~= "    mov    QWORD [r10+"
                    ~ getOffset(funcArgs, i).to!string ~ "], r8\n"
                    ~ "    mov    QWORD [r10+"
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
                    return "    mov    " ~ getWordSize(var.type) ~ " [rbp-"
                        ~ (getStackOffset(stackVars, i)).to!string ~ "], r8\n";
                }
                return "    mov    QWORD [rbp-"
                    ~ (getStackOffset(stackVars, i)).to!string ~ "], r8\n"
                    ~ "    mov    QWORD [rbp-"
                    ~ (getStackOffset(stackVars, i) + 8).to!string ~ "], r9\n";
            }
        }
        assert(false);
        return "";
    }
}

string compileFunction(FuncSig* sig, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    vars.closureVars = sig.closureVars;
    vars.funcArgs = sig.funcArgs;
    vars.stackVars = [];
    vars.retType = sig.returnType;
    vars.tempBytes = [];
    vars.refreshLabelCounter();
    auto func = "";
    func ~= sig.funcName ~ ":\n";
    func ~= q"EOS
    push   rbp         ; set up stack frame
    mov    rbp, rsp
EOS";
    sig.funcBodyBlocks.writeln;
    func ~= compileBlock(
        cast(BareBlockNode)sig.funcBodyBlocks.children[0], vars
    );
    func ~= q"EOS
    mov    rsp, rbp    ; takedown stack frame
    pop    rbp
    ret
EOS";
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
        str ~= "    mov     r10, " ~ vars.retType.getWordSize ~ " [rbp-"
            ~ vars.getStackPtrOffset.to!string ~ "]\n"
            ~ "    mov     " ~ vars.retType.getWordSize ~ "[rbp+"
            ~ (STACK_PROLOGUE_SIZE + environOffset).to!string ~ "], "
            ~ "r10" ~ vars.retType.size.getRRegSuffix ~ "\n";
    }
    // Handle the fat ptr case
    else if (vars.retType.size == 16)
    {
        str ~= "    mov     r10, " ~ vars.retType.getWordSize ~ " [rbp-"
            ~ vars.getStackPtrOffset.to!string ~ "]\n"
            ~ "    mov     r11, " ~ vars.retType.getWordSize ~ " [rbp-"
            ~ (vars.getStackPtrOffset + 8).to!string ~ "]\n"
            ~ "    mov     " ~ vars.retType.getWordSize ~ "[rbp+"
            ~ (STACK_PROLOGUE_SIZE + environOffset + 8).to!string ~ "], r10\n"
            ~ "    mov     " ~ vars.retType.getWordSize ~ "[rbp+"
            ~ (STACK_PROLOGUE_SIZE + environOffset).to!string ~ "], r11\n";
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
    return "";
}

string compileWhileStmt(WhileStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
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

        // TODO we need to either put the var value in r8 (and possibly r9), or
        // we need to just start putting everything on the stack (probably a
        // better idea)

        str = "    ; var infer assign [" ~ varName ~ "]\n" ~ str
            ~ vars.compileVarSet(varName);
    }
    else
    {

    }
    return str;
}

string compileAssignExisting(AssignExistingNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
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
            str ~= "    push   r8\n";
            str ~= "    push   r9\n";
            break;
        case TypeEnum.FLOAT:
            str ~= "    sub    rsp, 4\n";
            str ~= "    movss  dword [rsp], xmm0\n";
            break;
        case TypeEnum.DOUBLE:
            str ~= "    sub    rsp, 8\n";
            str ~= "    movsd  qword [rsp], xmm0\n";
            break;
        default:
            str ~= "    push   r8\n";
            break;
        }
    }
    auto intReg = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"];
    auto floatReg = ["xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6",
                     "xmm7"];


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
            break;
        case TypeEnum.FLOAT:
            break;
        case TypeEnum.DOUBLE:
            break;
        default:
            if (intRegIndex < intReg.length)
            {
                str ~= "    mov    " ~ intReg[intRegIndex]
                                     ~ ", [rsp+" ~ (i*8).to!string ~ "]\n";
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
    str ~= "    add    rsp, " ~ (((numArgs <= 6) ? numArgs : 6) * 8).to!string
                              ~ "\n";
    return str;
}
