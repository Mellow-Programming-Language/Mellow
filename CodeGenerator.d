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
// value into an assumed-allocated location just past where the arguments were
// placed. So, on the stack for a function call, we have:
// arg3
// arg2
// arg1
// arg0
// return value allocation
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

debug (COMPILE_TRACE)
{
    string traceIndent;
    enum tracer =
        `
        string funcName = __FUNCTION__;
        writeln(traceIndent, "Entered: ", funcName);
        traceIndent ~= "  ";
        scope(success)
        {
            traceIndent = traceIndent[0..$-2];
            writeln(traceIndent, "Exiting: ", funcName);
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

struct FuncVars
{
    VarTypePair*[] closureVars;
    VarTypePair*[] funcArgs;
    VarTypePair*[] stackVars;
    Type* retType;
    ulong[] tempBytes;
    private uint uniqLabelCounter;

    auto getUniqLabel()
    {
        return ".L" ~ (uniqLabelCounter++).to!string;
    }

    auto getUniqLabelSuffix()
    {
        return (uniqLabelCounter++).to!string;
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

string compileFunction(FuncSig* sig)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto vars = new FuncVars();
    vars.closureVars = sig.closureVars;
    vars.funcArgs = sig.funcArgs;
    vars.retType = sig.returnType;
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

string compileBlock(BareBlockNode block, FuncVars* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto code = "";
    foreach (statement; block.children)
    {
        code ~= compileStatement(cast(StatementNode)statement, vars);
    }
    return code;
}

string compileStatement(StatementNode statement, FuncVars* vars)
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

string compileReturn(ReturnStmtNode node, FuncVars* vars)
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

string compileIfStmt(IfStmtNode node, FuncVars* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileWhileStmt(WhileStmtNode node, FuncVars* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileForStmt(ForStmtNode node, FuncVars* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileForeachStmt(ForeachStmtNode node, FuncVars* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileMatchStmt(MatchStmtNode node, FuncVars* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileDeclaration(DeclarationNode node, FuncVars* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto child = node.children[0];
    if (cast(DeclTypeInferNode)child) {
        return compileDeclTypeInfer(cast(DeclTypeInferNode)child, vars);
    }
    return "";
}

string compileDeclTypeInfer(DeclTypeInferNode node, FuncVars* vars)
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

string compileAssignExisting(AssignExistingNode node, FuncVars* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileSpawnStmt(SpawnStmtNode node, FuncVars* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileYieldStmt(YieldStmtNode node, FuncVars* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileChanWrite(ChanWriteNode node, FuncVars* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileFuncCall(FuncCallNode node, FuncVars* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = compileArgList(cast(FuncCallArgListNode)node.children[1], vars);
    str ~= "    call   " ~ getIdentifier(cast(IdentifierNode)node.children[0])
                         ~ "\n";
    return str;
}

string compileArgList(FuncCallArgListNode node, FuncVars* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = node.children
                   .map!(a => compileExpression(cast(BoolExprNode)a, vars))
                   .reduce!((a, b) => a ~ b);
    return str;
}
