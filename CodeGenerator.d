import std.stdio;
import Function;
import typedecl;
import parser;
import visitor;
import utils;
import constants;
import std.conv;
import std.algorithm;
import std.array;
import std.range;
import ExprCodeGenerator;

// Note that arguments 0-5 are in registers rdi, rsi, rdx, rcx, r8, and r9. So,
// on the stack for a function call, we have:
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

// After compilation of any particular expression, the result will be in r8
// unless otherwise noted.

// Listing of caller-saved vs. callee-saved registers
// Caller-Saved        Callee-Saved
// ------------        ------------
// rax                 rbx
// rcx                 rbp
// rdx                 r12
// rsi                 r13
// rdi                 r14
// rsp                 r15
// r8
// r9
// r10
// r11

const RBP_SIZE = 8;
const RETURN_ADDRESS_SIZE = 8;
const STACK_PROLOGUE_SIZE = RBP_SIZE + RETURN_ADDRESS_SIZE;
const ENVIRON_PTR_SIZE = 8;

const INT_REG = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"];
const FLOAT_REG = ["xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6",
                   "xmm7"];
// This is used as a placeholder when generating code for return statements.
// Since we don't know how much temporary space is used by the function until
// after we generate code for the whole thing, and since we only allocate
// actual stack space (by actually subtracting from rsp) once at the beginning,
// this is used so we can modify the generated function code after-the-fact with
// the correct stack restore instructions
const STACK_RESTORE_PLACEHOLDER = "\n____STACK_RESTORE_PLACEHOLDER____\n";

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

// Assumes char length == 1 or 2, since the input should have been checked by
// the parser
auto getChar(string charRep)
{
    char code;
    if (charRep[0] == '\\')
    {
        switch (charRep[1])
        {
        case 'a':
            code = '\a';
            break;
        case 'b':
            code = '\b';
            break;
        case 'f':
            code = '\f';
            break;
        case 'n':
            code = '\n';
            break;
        case 'r':
            code = '\r';
            break;
        case 't':
            code = '\t';
            break;
        case 'v':
            code = '\v';
            break;
        case '\\':
            code = '\\';
            break;
        case '\'':
            code = '\\';
            break;
        case '"':
            code = '\"';
            break;
        case '?':
            code = '\?';
            break;
        case '0':
            code = '\0';
            break;
        default:
            code = charRep[1];
            break;
        }
    }
    else
    {
        code = charRep[0];
    }
    return code;
}

auto getOffset(VarTypePair*[] vars, ulong index)
{
    return getAlignedIndexOffset(vars.map!(a => a.type.size).array, index);
}

string compileRegSave(string[] regs, Context* vars)
{
    auto str = "";
    foreach (i, reg; regs)
    {
        vars.allocateStackSpace(8);
        str ~= "    mov    qword [rbp-" ~ vars.getTop.to!string
                                        ~ "], "
                                        ~ reg
                                        ~ "\n";
    }
    return str;
}

// This function assumes it is being called on the same array of strings in the
// same order as a previous call on compileRegSave
string compileRegRestore(string[] regs, Context* vars)
{
    auto str = "";
    foreach_reverse (i, reg; regs)
    {
        str ~= "    mov    " ~ reg
                             ~ ", qword [rbp-"
                             ~ vars.getTop.to!string
                             ~ "]\n";
        vars.deallocateStackSpace(8);
    }
    return str;
}

auto getTupleAllocSize(TupleType* type)
{
    return MARK_FUNC_PTR
        + STRUCT_BUFFER_SIZE
        + type.size;
}

auto getStructAllocSize(StructType* type)
{
    return MARK_FUNC_PTR
        + STRUCT_BUFFER_SIZE
        + type.size;
}

auto getVariantAllocSize(VariantType* type)
{
    return MARK_FUNC_PTR
         + VARIANT_TAG_SIZE
         + type.size;
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
    string[] ifEndBlockHasRunLabels;
    string[] matchEndBlockHasRunLabels;
    bool[string] runtimeExterns;
    bool[string] bssQWordAllocs;
    FuncSig*[string] externFuncs;
    FuncSig*[string] compileFuncs;
    StructType*[string] structDefs;
    VariantType*[string] variantDefs;
    VarTypePair*[] closureVars;
    VarTypePair*[] funcArgs;
    Type* retType;
    // Set when calculating l-value addresses, to determine how the assignment
    // should be made
    bool isStackAligned;
    uint reservedStackSpace;
    uint maxTempSpaceUsed;
    string valueTag;
    uint[] matchTypeLoc;
    string[] matchEndLabel;
    string[] matchNextWhenLabel;
    bool callUnittests;
    string[] unittestNames;
    bool release;
    private VarTypePair*[] stackVars;
    private uint topOfStack;
    private uint uniqLabelCounter;
    private uint uniqDataCounter;
    private string[] breakLabels;
    private string[] continueLabels;

    void resetState(FuncSig* sig)
    {
        closureVars = sig.closureVars;
        funcArgs = [];
        stackVars = [];
        topOfStack = 0;
        reservedStackSpace = sig.stackVarAllocSize;
        maxTempSpaceUsed = 0;
        retType = sig.returnType;
        uniqLabelCounter = 0;
    }

    auto getUniqDataLabel()
    {
        return "__S" ~ (uniqDataCounter++).to!string;
    }

    auto getUniqLabel()
    {
        return ".L" ~ (uniqLabelCounter++).to!string;
    }

    auto getTop()
    {
        return reservedStackSpace + topOfStack;
    }

    void allocateStackSpace(uint bytes)
    {
        topOfStack += bytes;
        if (topOfStack > maxTempSpaceUsed)
        {
            maxTempSpaceUsed = topOfStack;
        }
    }

    void deallocateStackSpace(uint bytes)
    {
        topOfStack -= bytes;
    }

    // Since the typechecker guarantees that no variable is ever shadowing
    // another, we are free to replace variables with the same name
    void addStackVar(VarTypePair* newVar)
    {
        long replaceIndex = -1;
        foreach (i, var; stackVars)
        {
            if (var.varName == newVar.varName)
            {
                replaceIndex = i.to!long;
                break;
            }
        }
        if (replaceIndex >= 0)
        {
            stackVars[replaceIndex] = newVar;
        }
        else
        {
            stackVars ~= newVar;
        }
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

    bool isFuncName(string name)
    {
        foreach (func; externFuncs.values)
        {
            if (func.funcName == name)
            {
                return true;
            }
        }
        foreach (func; compileFuncs.values)
        {
            if (func.funcName == name)
            {
                return true;
            }
        }
        return false;
    }

    bool isVarName(string name)
    {
        foreach (var; closureVars)
        {
            if (var.varName == name)
            {
                return true;
            }
        }
        foreach (var; funcArgs)
        {
            if (var.varName == name)
            {
                return true;
            }
        }
        foreach (var; stackVars)
        {
            if (var.varName == name)
            {
                return true;
            }
        }
        return false;
    }

    // Because we've passed the typecheck stage, we're guaranteed that lookup
    // will succeed. Get the variable in r8
    string compileVarGet(string varName)
    {
        const environOffset = (closureVars.length > 0)
                           ? ENVIRON_PTR_SIZE
                           : 0;
        const retValOffset = retType.size;
        auto str = "";
        foreach (i, var; funcArgs)
        {
            if (varName == var.varName)
            {
                str ~= "    mov    r8, qword [rbp+"
                    ~ (STACK_PROLOGUE_SIZE + environOffset + retValOffset +
                       getOffset(funcArgs, i)).to!string ~ "]\n";
                if (var.type.needsSignExtend)
                {
                    str ~= "    movsx  r8, r8"
                        ~ getRRegSuffix(var.type.size)
                        ~ "\n";
                }
            }
        }
        foreach (i, var; closureVars)
        {
            if (varName == var.varName)
            {
                str ~= "    mov    r10, [rbp+16]\n";
                str ~= "    mov    r8, qword [r10+"
                    ~ getOffset(closureVars, i).to!string ~ "]\n";
                if (var.type.needsSignExtend)
                {
                    str ~= "    movsx  r8, r8"
                        ~ getRRegSuffix(var.type.size)
                        ~ "\n";
                }
            }
        }
        foreach (i, var; stackVars)
        {
            if (varName == var.varName)
            {
                str ~= "    mov    r8, qword [rbp-"
                    ~ ((i + 1) * 8).to!string ~ "]\n";
                if (var.type.needsSignExtend)
                {
                    str ~= "    movsx  r8, r8"
                        ~ getRRegSuffix(var.type.size)
                        ~ "\n";
                }
            }
        }
        return str;
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
                return "    mov    r8, rbp\n"
                     ~ "    add    r8, "
                     ~ (STACK_PROLOGUE_SIZE
                        + environOffset
                        + retValOffset
                        + getOffset(funcArgs, i)).to!string
                     ~ "\n";
            }
        }
        foreach (i, var; closureVars)
        {
            if (varName == var.varName)
            {
                auto str = "    mov    r10, [rbp+16]\n";
                str ~= "    mov    r8, r10\n";
                str ~= "    add    r8, "
                    ~ getOffset(closureVars, i).to!string ~ "\n";
                return str;
            }
        }
        foreach (i, var; stackVars)
        {
            if (varName == var.varName)
            {
                auto str = "";
                str ~= "    lea    r8, [rbp-" ~ ((i + 1) * 8).to!string ~ "]\n";
                return str;
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

string compileGetCurrentThread(string reg, Context* vars)
{
    version (MULTITHREAD)
    {
        vars.runtimeExterns["get_currentthread"] = true;
    }
    else
    {
        vars.runtimeExterns["currentthread"] = true;
    }
    auto str = "";
    version (MULTITHREAD)
    {
        str ~= "    call   get_currentthread\n";
        if (reg != "rax")
        {
            str ~= "    mov    " ~ reg ~ ", rax\n";
        }
    }
    else
    {
        str ~= "    mov    " ~ reg ~ ", qword [currentthread]\n";
    }
    return str;
}

// Using only the given register (and rax), populate the given register with
// a pointer to the GC_Env struct ptr for this green thread
string compileGetGCEnv(string reg, Context* vars)
{
    vars.runtimeExterns["__GC_malloc"] = true;
    vars.runtimeExterns["__GC_track"] = true;
    auto str = compileGetCurrentThread(reg, vars);
    str ~= "    mov    " ~ reg ~ ", qword [" ~ reg ~ "]\n";
    return str;
}

// Compile the function prologue, which will grow the stack if necessary
string compilePrologue(uint stackAlignedAlloc, Context* vars)
{
    vars.runtimeExterns["__realloc_stack"] = true;
    auto str = "";
    str ~= "    ; FUNCTION PROLOGUE (do we need to grow the stack?):\n";
    str ~= "    sub    rsp, 16\n";
    str ~= "    ; Preserve function argument registers (need extra scratch regs)\n";
    str ~= "    mov    qword [rbp-8], rdi\n";
    str ~= "    mov    qword [rbp-16], rcx\n";
    str ~= "    ; Get current rsp in rdi and t_StackBot in r10\n";
    str ~= compileGetCurrentThread("rax", vars);
    str ~= "    mov    rdi, rsp\n";
    str ~= "    mov    r10, qword [rax+16]\n";
    str ~= "    ; Get stackSize in cl (rcx), and the stack size in bytes in r11\n";
    str ~= "    mov    rcx, 0\n";
    str ~= "    mov    cl, byte [rax+49]\n";
    str ~= "    mov    r11, 1\n";
    str ~= "    shl    r11, cl\n";
    str ~= "    ; Get delta between bottom of stack and current rsp (used space)\n";
    str ~= "    sub    r10, rdi\n";
    str ~= "    ; Get the amount of leftover space\n";
    str ~= "    sub    r11, r10\n";
    str ~= "    ; Check if we'd be allocating more space than we have left\n";
    auto allocsTooBigLabel = vars.getUniqLabel;
    str ~= "    cmp    r11, " ~ stackAlignedAlloc.to!string ~ "\n";
    str ~= "    jle    " ~ allocsTooBigLabel ~ "\n";
    str ~= "    ; Get amount of space left after this function makes stack allocs\n";
    str ~= "    sub    r11, " ~ stackAlignedAlloc.to!string ~ "\n" ;
    // NOTE: C function calls are possible only after having 'extern' declared
    // the function. Any 'extern' declared function is executed on the OS stack,
    // which grows for us, so we don't need to worry about stack-growing or
    // running off the end of the stack
    str ~= "    ; If we're bumping up against the edge of our allocated stack,\n";
    str ~= "    ; minus a 512 byte buffer, then exec the realloc routine.\n";
    str ~= "    cmp    r11, 512\n";
    auto skipReallocLabel = vars.getUniqLabel;
    str ~= "    jg     " ~ skipReallocLabel ~ "\n";
    str ~= allocsTooBigLabel ~ ":\n";
    str ~= "    ; Preserve the rest of the function arguments\n";
    str ~= "    sub    rsp, 32\n";
    str ~= "    mov    qword [rbp-24], rsi\n";
    str ~= "    mov    qword [rbp-32], rdx\n";
    str ~= "    mov    qword [rbp-40], r8\n";
    str ~= "    mov    qword [rbp-48], r9\n";
    str ~= "    ; We need to pass the ThreadData* curThread, which happens to\n";
    str ~= "    ; already be in rax\n";
    str ~= "    mov    rdi, rax\n";
    str ~= "    call   __realloc_stack\n";
    str ~= "    ; Restore the rest of the function arguments\n";
    str ~= "    mov    rsi, qword [rbp-24]\n";
    str ~= "    mov    rdx, qword [rbp-32]\n";
    str ~= "    mov    r8, qword [rbp-40]\n";
    str ~= "    mov    r9, qword [rbp-48]\n";
    str ~= "    add    rsp, 32\n";
    str ~= skipReallocLabel ~ ":\n";
    str ~= "    ; Restore last function argument register\n";
    str ~= "    mov    rdi, qword [rbp-8]\n";
    str ~= "    mov    rcx, qword [rbp-16]\n";
    str ~= "    add    rsp, 16\n";
    str ~= "    ; END FUNCTION PROLOGUE\n";
    return str;
}

string compileFunction(FuncSig* sig, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto funcHeader = "";
    // If the function is not a template (otherwise instantiations of the same
    // template in different files would yield a name-conflict linking error)
    // then make it globally available. By definition, template instantiations
    // should only be available local to the file
    if (sig.templateParams.length == 0)
    {
        funcHeader ~= "    global " ~ sig.funcName ~ "\n";
    }
    funcHeader ~= sig.funcName ~ ":\n";
    funcHeader ~= "    push   rbp         ; set up stack frame\n";
    funcHeader ~= "    mov    rbp, rsp\n";
    auto funcHeader_2 = "";
    auto intRegIndex = 0;
    auto floatRegIndex = 0;
    vars.resetState(sig);

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
                vars.addStackVar(arg);
                // r8 is one of the potential func arg input registers, so store
                // it temporarily in a free register while we use it to put the
                // arg on the stack
                funcHeader_2 ~= "    mov    r10, r8\n";
                funcHeader_2 ~= "    movsd  r8, " ~ FLOAT_REG[intRegIndex]
                                                  ~ "\n";
                funcHeader_2 ~= vars.compileVarSet(arg.varName);
                funcHeader_2 ~= "    mov    r8, r10\n";
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
                vars.addStackVar(arg);
                // r8 is one of the potential func arg input registers, so store
                // it temporarily in a free register while we use it to put the
                // arg on the stack
                funcHeader_2 ~= "    mov    r10, r8\n";
                funcHeader_2 ~= "    mov    r8, " ~ INT_REG[intRegIndex]
                                                  ~ "\n";
                funcHeader_2 ~= vars.compileVarSet(arg.varName);
                funcHeader_2 ~= "    mov    r8, r10\n";
                intRegIndex++;
            }
        }
    }

    // If this is the main function and we were passed argv: []string, we need
    // to claim argv in the GC, which means adding the array ptr to GC, and each
    // string element to the GC
    if (sig.funcName == "__mellow_main" && sig.funcArgs.length > 0)
    {
        vars.runtimeExterns["__GC_mellow_add_alloc"] = true;
        auto argvName = sig.funcArgs[0].varName;
        funcHeader_2 ~=
            "    ; BEGIN: Add [" ~ argvName ~ "] (main() argv) to GC\n";
        // Get the argv variable in r8
        funcHeader_2 ~= vars.compileVarGet(argvName);
        // Get array length
        funcHeader_2 ~= "    mov    r9, qword [r8+" ~ MARK_FUNC_PTR.to!string
                                                    ~ "]\n";
        // Initialize a counter
        funcHeader_2 ~= "    mov    r10, 0\n";
        vars.allocateStackSpace(8);
        auto argvLoc = vars.getTop.to!string;
        vars.allocateStackSpace(8);
        auto argvLenLoc = vars.getTop.to!string;
        vars.allocateStackSpace(8);
        auto argvIndexLoc = vars.getTop.to!string;
        scope (exit) vars.deallocateStackSpace(24);
        funcHeader_2 ~= "    mov    qword [rbp-" ~ argvLoc ~ "], r8\n";
        funcHeader_2 ~= "    mov    qword [rbp-" ~ argvLenLoc ~ "], r9\n";
        funcHeader_2 ~= "    mov    qword [rbp-" ~ argvIndexLoc ~ "], r10\n";
        // Calculate total size of array allocation: Array length * 8 bytes per
        // string ptr + object header
        funcHeader_2 ~= "    mov    rdi, r8\n";
        funcHeader_2 ~= "    mov    rsi, r9\n";
        funcHeader_2 ~= "    imul   rsi, " ~ MELLOW_PTR_SIZE.to!string ~ "\n";
        funcHeader_2 ~= "    add    rsi, " ~ OBJ_HEAD_SIZE.to!string ~ "\n";
        // Add array pointer to GC allocation list
        funcHeader_2 ~= compileGetGCEnv("rdx", vars);
        funcHeader_2 ~= "    call   __GC_mellow_add_alloc\n";
        auto loopLabel = vars.getUniqLabel;
        auto endLoopLabel = vars.getUniqLabel;
        funcHeader_2 ~= loopLabel ~ ":\n";
        // Get array ptr, array length, and counter
        funcHeader_2 ~= "    mov    r8, qword [rbp-" ~ argvLoc ~ "]\n";
        funcHeader_2 ~= "    mov    r9, qword [rbp-" ~ argvLenLoc ~ "]\n";
        funcHeader_2 ~= "    mov    r10, qword [rbp-" ~ argvIndexLoc ~ "]\n";
        funcHeader_2 ~= "    cmp    r10, r9\n";
        funcHeader_2 ~= "    je     " ~ endLoopLabel ~ "\n";
        // Get next string in array
        funcHeader_2 ~= "    mov    rdi, r10\n";
        funcHeader_2 ~= "    imul   rdi, " ~ MELLOW_PTR_SIZE.to!string ~ "\n";
        funcHeader_2 ~= "    add    rdi, " ~ OBJ_HEAD_SIZE.to!string ~ "\n";
        // Add offset to argv itself, to get address of string in array
        funcHeader_2 ~= "    add    rdi, r8\n";
        // Index into argv to extract string into rdi
        funcHeader_2 ~= "    mov    rdi, qword [rdi]\n";
        // Increment index counter
        funcHeader_2 ~= "    add    r10, 1\n";
        funcHeader_2 ~= "    mov    qword [rbp-" ~ argvIndexLoc ~ "], r10\n";
        // Get string size
        funcHeader_2 ~= "    mov    rsi, qword [rdi+" ~ MARK_FUNC_PTR.to!string
                                                      ~ "]\n";
        // Add in object header and null byte
        funcHeader_2 ~= "    add    rsi, " ~ (OBJ_HEAD_SIZE + 1).to!string
                                           ~ "\n";
        // Add string to GC allocations
        funcHeader_2 ~= compileGetGCEnv("rdx", vars);
        funcHeader_2 ~= "    call   __GC_mellow_add_alloc\n";
        funcHeader_2 ~= "    jmp    " ~ loopLabel ~ "\n";
        funcHeader_2 ~= endLoopLabel ~ ":\n";
        funcHeader_2 ~=
            "    ; END: Add [" ~ argvName ~ "] (main() argv) to GC\n";
    }

    // TODO handle the other block cases
    string funcDef;
    // Unittest case
    if (cast(BareBlockNode)sig.funcDefNode.children[0])
    {
        funcDef = compileBlock(
            cast(BareBlockNode)(sig.funcDefNode.children[0]), vars
        );
    }
    // Real function case
    else if (cast(FuncBodyBlocksNode)sig.funcDefNode.children[1])
    {
        auto funcBodyBlocks = cast(FuncBodyBlocksNode)sig.funcDefNode
                                                         .children[1];
        funcDef = compileBlock(
            cast(BareBlockNode)funcBodyBlocks.children[0], vars
        );
    }
    // Determine the total amount of stack space used by the function at max
    auto totalStackSpaceUsed = sig.stackVarAllocSize + vars.maxTempSpaceUsed;
    // Allocate space on the stack, keeping the stack in 16-byte alignment
    auto stackAlignedAlloc = totalStackSpaceUsed + (totalStackSpaceUsed % 16);
    auto stackRestoreStr = "    add    rsp, " ~ stackAlignedAlloc.to!string
                                           ~ "\n";
    funcHeader ~= compilePrologue(stackAlignedAlloc, vars);
    funcHeader ~= "    sub    rsp, " ~ stackAlignedAlloc.to!string ~ "\n";

    funcDef = replace(funcDef, STACK_RESTORE_PLACEHOLDER, stackRestoreStr);
    auto funcFooter = "";
    funcFooter ~= stackRestoreStr;
    funcFooter ~= "    mov    rsp, rbp    ; takedown stack frame\n";
    funcFooter ~= "    pop    rbp\n";
    funcFooter ~= "    ret\n";
    return funcHeader ~ funcHeader_2 ~ funcDef ~ funcFooter;
}

string compileBlock(BareBlockNode block, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto code = "";
    foreach (statement; block.children)
    {
        code ~= compileFuncDefOrStmt(cast(FuncDefOrStmtNode)statement, vars);
    }
    return code;
}

string compileFuncDefOrStmt(FuncDefOrStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);

    auto child = node.children[0];

    if (cast(StatementNode)child)
        return compileStatement(cast(StatementNode)child, vars);
    else if (cast(FuncDefNode)child)
        assert(false, "Unimplemented");
    assert(false);
    return "";
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
    else if (cast(AssertStmtNode)child)
        return compileAssertStmt(cast(AssertStmtNode)child, vars);
    else if (cast(SpawnStmtNode)child)
        return compileSpawnStmt(cast(SpawnStmtNode)child, vars);
    else if (cast(YieldStmtNode)child)
        return compileYieldStmt(cast(YieldStmtNode)child, vars);
    else if (cast(BreakStmtNode)child)
        return compileBreakStmt(cast(BreakStmtNode)child, vars);
    else if (cast(ContinueStmtNode)child)
        return compileContinueStmt(cast(ContinueStmtNode)child, vars);
    else if (cast(ChanWriteNode)child)
        return compileChanWrite(cast(ChanWriteNode)child, vars);
    else if (cast(FuncCallNode)child)
        return compileFuncCall(cast(FuncCallNode)child, vars);
    assert(false);
    return "";
}

string compileAssertStmt(AssertStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    if (vars.release)
    {
        return "";
    }
    auto str = "";
    vars.runtimeExterns["printf"] = true;
    auto assertEndlabel = vars.getUniqLabel();
    auto assertStrLabel = vars.getUniqDataLabel();
    auto entry = new DataEntry();
    entry.label = assertStrLabel;
    entry.data = DataEntry.toNasmDataString(
        "Assert " ~ errorHeader(node)
    );
    vars.dataEntries ~= entry;
    str ~= compileExpression(cast(BoolExprNode)node.children[0], vars);
    str ~= "    cmp    r8, 0\n";
    str ~= "    jne    " ~ assertEndlabel ~ "\n";
    str ~= "    mov    rdi, " ~ assertStrLabel ~ "\n";
    str ~= "    call   printf\n";
    str ~= "    mov    rdi, __NEWLINE\n";
    str ~= "    call   printf\n";
    if (node.children.length > 1)
    {
        str ~= compileExpression(cast(BoolExprNode)node.children[1], vars);
        str ~= "    add    r8, " ~ (MARK_FUNC_PTR + STR_SIZE).to!string
                                 ~ "\n";
        str ~= "    mov    rdi, r8\n";
        str ~= "    call   printf\n";
        str ~= "    mov    rdi, __NEWLINE\n";
        str ~= "    call   printf\n";
    }
    str ~= "    mov    rdi, 1\n";
    str ~= "    call   exit\n";
    str ~= assertEndlabel ~ ":\n";
    return str;

}

string compileReturn(ReturnStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    if (node.children.length == 0)
    {
       return STACK_RESTORE_PLACEHOLDER
            ~ "    mov    rsp, rbp    ; takedown stack frame\n"
            ~ "    pop    rbp\n"
            ~ "    ret\n";
    }
    const environOffset = (vars.closureVars.length > 0)
                        ? ENVIRON_PTR_SIZE
                        : 0;
    auto str = "";
    str ~= compileExpression(cast(BoolExprNode)node.children[0], vars);
    str ~= "    mov    rax, r8\n";
    str ~= STACK_RESTORE_PLACEHOLDER;
    str ~= "    mov    rsp, rbp    ; takedown stack frame\n";
    str ~= "    pop    rbp\n";
    str ~= "    ret\n";
    return str;
}

string compileIfStmt(IfStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    // Allocate space for and set the hasRun value, which tracks whether the
    // if-else-if chain executed any blocks or not
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto hasRun = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ hasRun ~ "], 0\n";
    vars.ifEndBlockHasRunLabels ~= hasRun;
    scope (exit) vars.ifEndBlockHasRunLabels.length--;
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
    // We're officially about to execute the if-stmt block, so set hasRun
    str ~= "    mov    qword [rbp-" ~ hasRun ~ "], 1\n";
    str ~= compileStatement(cast(StatementNode)node.children[2], vars);
    str ~= "    jmp    " ~ blockEndLabel ~ "\n";
    str ~= blockNextLabel ~ ":\n";
    str ~= compileElseIfs(cast(ElseIfsNode)node.children[3], vars);
    str ~= blockEndLabel ~ ":\n";
    vars.blockEndLabels.length--;
    if (node.children.length > 4)
    {
        // hasRun may have been set either when executing the if-stmt block,
        // or when executing an else-if-stmt block, or not at all
        str ~= "    mov    r8, qword [rbp-" ~ hasRun ~ "]\n";
        str ~= compileEndBlocks(cast(EndBlocksNode)node.children[4], vars);
    }
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
    // We're officially about to execute the else-if-stmt block, so set hasRun
    str ~= "    mov    qword [rbp-" ~ vars.ifEndBlockHasRunLabels[$-1]
                                    ~ "], 1\n";
    str ~= compileStatement(cast(StatementNode)node.children[2], vars);
    str ~= "    jmp    " ~ vars.blockEndLabels[$-1] ~ "\n";
    str ~= blockNextLabel ~ ":\n";
    return str;
}

string compileWhileStmt(WhileStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto blockLoopLabel = vars.getUniqLabel();
    auto blockEndLabel = vars.getUniqLabel();
    vars.breakLabels ~= [blockEndLabel];
    vars.continueLabels ~= [blockLoopLabel];
    auto str = "";
    str ~= compileCondAssignments(
        cast(CondAssignmentsNode)node.children[0], vars
    );
    // Allocate space for and set the hasRun value, which tracks whether the
    // loop has looped or not
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto hasRun = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ hasRun ~ "], 0\n";
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
    // We're officially about to execute the block of the loop, so set hasRun
    str ~= "    mov    qword [rbp-" ~ hasRun ~ "], 1\n";
    str ~= compileStatement(cast(StatementNode)node.children[2], vars);
    str ~= "    jmp    " ~ blockLoopLabel ~ "\n";
    str ~= blockEndLabel ~ ":\n";
    vars.breakLabels.length--;
    vars.continueLabels.length--;
    // If we have an EndBlocks chain, then move hasRun into r8 and compile the
    // chain
    if (cast(EndBlocksNode)node.children[$-1])
    {
        str ~= "    mov    r8, qword [rbp-" ~ hasRun ~ "]\n";
        str ~= compileEndBlocks(
            cast(EndBlocksNode)node.children[$-1], vars
        );
    }
    return str;
}

string compileForStmt(ForStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    // This one is the one that `continue` will loop to
    auto blockLoopLabel = vars.getUniqLabel();
    // This one is what we'll actually use for looping to
    auto blockRealLoopLabel = vars.getUniqLabel();
    auto blockEndLabel = vars.getUniqLabel();
    vars.breakLabels ~= [blockEndLabel];
    vars.continueLabels ~= [blockLoopLabel];
    auto str = "";
    auto nodeIndex = 0;
    str ~= compileCondAssignments(
        cast(CondAssignmentsNode)node.children[nodeIndex], vars
    );
    nodeIndex++;
    // Allocate space for and set the hasRun value, which tracks whether the
    // loop has looped or not
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto hasRun = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ hasRun ~ "], 0\n";
    str ~= blockRealLoopLabel ~ ":\n";
    // If we do have the conditional, then test it. If we don't have the
    // conditional, simply fall through to the block
    if (cast(BoolExprNode)node.children[nodeIndex])
    {
        str ~= compileBoolExpr(
            cast(BoolExprNode)node.children[nodeIndex], vars
        );
        str ~= "    cmp    r8, 0\n";
        // If it's zero, then it's false, meaning don't enter the loop
        str ~= "    je     " ~ blockEndLabel ~ "\n";
        nodeIndex++;
    }
    auto updateStmt = "";
    if (cast(ForUpdateStmtNode)node.children[nodeIndex])
    {
        updateStmt ~= compileForUpdateStmt(
            cast(ForUpdateStmtNode)node.children[nodeIndex], vars
        );
        nodeIndex++;
    }
    // We're officially about to execute the block of the loop, so set hasRun
    str ~= "    mov    qword [rbp-" ~ hasRun ~ "], 1\n";
    str ~= compileStatement(cast(StatementNode)node.children[nodeIndex], vars);
    str ~= blockLoopLabel ~ ":\n";
    str ~= updateStmt;
    str ~= "    jmp    " ~ blockRealLoopLabel ~ "\n";
    str ~= blockEndLabel ~ ":\n";
    vars.breakLabels.length--;
    vars.continueLabels.length--;
    // If we have an EndBlocks chain, then move hasRun into r8 and compile the
    // chain
    if (cast(EndBlocksNode)node.children[$-1])
    {
        str ~= "    mov    r8, qword [rbp-" ~ hasRun ~ "]\n";
        str ~= compileEndBlocks(
            cast(EndBlocksNode)node.children[$-1], vars
        );
    }
    return str;
}

string compileForUpdateStmt(ForUpdateStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    foreach (child; node.children)
    {
        str ~= compileAssignExisting(cast(AssignExistingNode)child, vars);
    }
    return str;
}

// For all of these, we assume a value is in r8, such that if the value is  non-
// zero, we executed the block or chain these were attached to at least once.
// So, we executed the if or one of the else ifs in an if chain, or one of the
// arms matched in a match statement, or the while, for, or foreach loop looped
// at least once
string compileEndBlocks(EndBlocksNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    if (cast(ThenElseCodaNode)node.children[0])
    {
        str ~= compileThenElseCoda(
            cast(ThenElseCodaNode)node.children[0], vars
        );
    }
    else if (cast(ThenCodaElseNode)node.children[0])
    {
        str ~= compileThenCodaElse(
            cast(ThenCodaElseNode)node.children[0], vars
        );
    }
    else if (cast(ElseThenCodaNode)node.children[0])
    {
        str ~= compileElseThenCoda(
            cast(ElseThenCodaNode)node.children[0], vars
        );
    }
    else if (cast(ElseCodaThenNode)node.children[0])
    {
        str ~= compileElseCodaThen(
            cast(ElseCodaThenNode)node.children[0], vars
        );
    }
    else if (cast(CodaElseThenNode)node.children[0])
    {
        str ~= compileCodaElseThen(
            cast(CodaElseThenNode)node.children[0], vars
        );
    }
    else if (cast(CodaThenElseNode)node.children[0])
    {
        str ~= compileCodaThenElse(
            cast(CodaThenElseNode)node.children[0], vars
        );
    }
    else if (cast(ThenElseNode)node.children[0])
    {
        str ~= compileThenElse(cast(ThenElseNode)node.children[0], vars);
    }
    else if (cast(ThenCodaNode)node.children[0])
    {
        str ~= compileThenCoda(cast(ThenCodaNode)node.children[0], vars);
    }
    else if (cast(ElseThenNode)node.children[0])
    {
        str ~= compileElseThen(cast(ElseThenNode)node.children[0], vars);
    }
    else if (cast(ElseCodaNode)node.children[0])
    {
        str ~= compileElseCoda(cast(ElseCodaNode)node.children[0], vars);
    }
    else if (cast(CodaThenNode)node.children[0])
    {
        str ~= compileCodaThen(cast(CodaThenNode)node.children[0], vars);
    }
    else if (cast(CodaElseNode)node.children[0])
    {
        str ~= compileCodaElse(cast(CodaElseNode)node.children[0], vars);
    }
    else if (cast(ThenBlockNode)node.children[0])
    {
        str ~= compileThenBlock(cast(ThenBlockNode)node.children[0], vars);
    }
    else if (cast(ElseBlockNode)node.children[0])
    {
        str ~= compileElseBlock(cast(ElseBlockNode)node.children[0], vars);
    }
    else if (cast(CodaBlockNode)node.children[0])
    {
        str ~= compileCodaBlock(cast(CodaBlockNode)node.children[0], vars);
    }
    return str;
}

string compileThenElseCoda(ThenElseCodaNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto hasRun = vars.getTop.to!string;
    auto codaLabel = vars.getUniqLabel;
    auto endLabel = vars.getUniqLabel;
    auto str = "";
    str ~= "    mov    qword [rbp-" ~ hasRun ~ "], r8\n";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    str ~= "    mov    r8, qword [rbp-" ~ hasRun ~ "]\n";
    str ~= "    cmp    r8, 0\n";
    str ~= "    jne    " ~ codaLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[1], vars);
    str ~= "    jmp    " ~ endLabel ~ "\n";
    str ~= codaLabel ~ ":\n";
    str ~= compileStatement(cast(StatementNode)node.children[2], vars);
    str ~= endLabel ~ ":\n";
    return str;
}

string compileThenCodaElse(ThenCodaElseNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto hasRun = vars.getTop.to!string;
    auto elseLabel = vars.getUniqLabel;
    auto endLabel = vars.getUniqLabel;
    auto str = "";
    str ~= "    mov    qword [rbp-" ~ hasRun ~ "], r8\n";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    str ~= "    mov    r8, qword [rbp-" ~ hasRun ~ "]\n";
    str ~= "    cmp    r8, 0\n";
    str ~= "    je     " ~ elseLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[1], vars);
    str ~= "    jmp    " ~ endLabel ~ "\n";
    str ~= elseLabel ~ ":\n";
    str ~= compileStatement(cast(StatementNode)node.children[2], vars);
    str ~= endLabel ~ ":\n";
    return str;
}

string compileElseThenCoda(ElseThenCodaNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto hasRun = vars.getTop.to!string;
    auto thenLabel = vars.getUniqLabel;
    auto endLabel = vars.getUniqLabel;
    auto str = "";
    str ~= "    mov    qword [rbp-" ~ hasRun ~ "], r8\n";
    str ~= "    cmp    r8, 0\n";
    str ~= "    jne    " ~ thenLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    str ~= thenLabel ~ ":\n";
    str ~= compileStatement(cast(StatementNode)node.children[1], vars);
    str ~= "    mov    r8, qword [rbp-" ~ hasRun ~ "]\n";
    str ~= "    cmp    r8, 0\n";
    str ~= "    je     " ~ endLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[2], vars);
    str ~= endLabel ~ ":\n";
    return str;
}

string compileElseCodaThen(ElseCodaThenNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto codaLabel = vars.getUniqLabel;
    auto thenLabel = vars.getUniqLabel;
    auto str = "";
    str ~= "    cmp    r8, 0\n";
    str ~= "    jne    " ~ codaLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    str ~= "    jmp    " ~ thenLabel ~ "\n";
    str ~= codaLabel ~ ":\n";
    str ~= compileStatement(cast(StatementNode)node.children[1], vars);
    str ~= thenLabel ~ ":\n";
    str ~= compileStatement(cast(StatementNode)node.children[2], vars);
    return str;
}

string compileCodaElseThen(CodaElseThenNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto elseLabel = vars.getUniqLabel;
    auto thenLabel = vars.getUniqLabel;
    auto str = "";
    str ~= "    cmp    r8, 0\n";
    str ~= "    je     " ~ elseLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    str ~= "    jmp    " ~ thenLabel ~ "\n";
    str ~= elseLabel ~ ":\n";
    str ~= compileStatement(cast(StatementNode)node.children[1], vars);
    str ~= thenLabel ~ ":\n";
    str ~= compileStatement(cast(StatementNode)node.children[2], vars);
    return str;
}

string compileCodaThenElse(CodaThenElseNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto hasRun = vars.getTop.to!string;
    auto thenLabel = vars.getUniqLabel;
    auto endLabel = vars.getUniqLabel;
    auto str = "";
    str ~= "    mov    qword [rbp-" ~ hasRun ~ "], r8\n";
    str ~= "    cmp    r8, 0\n";
    str ~= "    je     " ~ thenLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    str ~= thenLabel ~ ":\n";
    str ~= compileStatement(cast(StatementNode)node.children[1], vars);
    str ~= "    mov    r8, qword [rbp-" ~ hasRun ~ "]\n";
    str ~= "    cmp    r8, 0\n";
    str ~= "    jne    " ~ endLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[2], vars);
    str ~= endLabel ~ ":\n";
    return str;
}

string compileThenElse(ThenElseNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto hasRun = vars.getTop.to!string;
    auto endLabel = vars.getUniqLabel;
    auto str = "";
    str ~= "    mov    qword [rbp-" ~ hasRun ~ "], r8\n";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    str ~= "    mov    r8, qword [rbp-" ~ hasRun ~ "]\n";
    str ~= "    cmp    r8, 0\n";
    str ~= "    jne    " ~ endLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[1], vars);
    str ~= endLabel ~ ":\n";
    return str;
}

string compileThenCoda(ThenCodaNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto hasRun = vars.getTop.to!string;
    auto endLabel = vars.getUniqLabel;
    auto str = "";
    str ~= "    mov    qword [rbp-" ~ hasRun ~ "], r8\n";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    str ~= "    mov    r8, qword [rbp-" ~ hasRun ~ "]\n";
    str ~= "    cmp    r8, 0\n";
    str ~= "    je     " ~ endLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[1], vars);
    str ~= endLabel ~ ":\n";
    return str;
}

string compileElseThen(ElseThenNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto thenLabel = vars.getUniqLabel;
    auto str = "";
    str ~= "    cmp    r8, 0\n";
    str ~= "    jne    " ~ thenLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    str ~= thenLabel ~ ":\n";
    str ~= compileStatement(cast(StatementNode)node.children[1], vars);
    return str;
}

string compileElseCoda(ElseCodaNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto codaLabel = vars.getUniqLabel;
    auto endLabel = vars.getUniqLabel;
    auto str = "";
    str ~= "    cmp    r8, 0\n";
    str ~= "    jne    " ~ codaLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    str ~= "    jmp    " ~ endLabel ~ "\n";
    str ~= codaLabel ~ ":\n";
    str ~= compileStatement(cast(StatementNode)node.children[1], vars);
    str ~= endLabel ~ ":\n";
    return str;
}

string compileCodaThen(CodaThenNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto thenLabel = vars.getUniqLabel;
    auto str = "";
    str ~= "    cmp    r8, 0\n";
    str ~= "    je     " ~ thenLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    str ~= thenLabel ~ ":\n";
    str ~= compileStatement(cast(StatementNode)node.children[1], vars);
    return str;
}

string compileCodaElse(CodaElseNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto endLabel = vars.getUniqLabel;
    auto elseLabel = vars.getUniqLabel;
    auto str = "";
    str ~= "    cmp    r8, 0\n";
    str ~= "    je     " ~ elseLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    str ~= "    jmp    " ~ endLabel ~ "\n";
    str ~= elseLabel ~ ":\n";
    str ~= compileStatement(cast(StatementNode)node.children[1], vars);
    str ~= endLabel ~ ":\n";
    return str;
}

string compileThenBlock(ThenBlockNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    return str;
}

string compileElseBlock(ElseBlockNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto endElseLabel = vars.getUniqLabel;
    auto str = "";
    str ~= "    cmp    r8, 0\n";
    str ~= "    jne    " ~ endElseLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    str ~= endElseLabel ~ ":\n";
    return str;
}

string compileCodaBlock(CodaBlockNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto endCodaLabel = vars.getUniqLabel;
    auto str = "";
    str ~= "    cmp    r8, 0\n";
    str ~= "    je     " ~ endCodaLabel ~ "\n";
    str ~= compileStatement(cast(StatementNode)node.children[0], vars);
    str ~= endCodaLabel ~ ":\n";
    return str;
}

string compileForeachStmt(ForeachStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    auto loopType = node.data["type"].get!(Type*);
    auto foreachArgs = node.data["argnames"].get!(string[]);
    auto hasIndex = node.data["hasindex"].get!(bool);
    auto indexVarName = "";
    if (hasIndex)
    {
        indexVarName = foreachArgs[0];
        foreachArgs = foreachArgs[1..$];
        auto indexType = new Type();
        indexType.tag = TypeEnum.INT;
        auto indexVar = new VarTypePair();
        indexVar.varName = indexVarName;
        indexVar.type = indexType;
        vars.addStackVar(indexVar);
    }
    auto foreachLoop = vars.getUniqLabel;
    auto endForeach = vars.getUniqLabel;
    vars.breakLabels ~= [endForeach];
    vars.continueLabels ~= [foreachLoop];
    // Allocate space for and set the hasRun value, which tracks whether the
    // loop has looped or not
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto hasRun = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ hasRun ~ "], 0\n";
    str ~= compileCondAssignments(
        cast(CondAssignmentsNode)node.children[0], vars
    );
    str ~= compileBoolExpr(cast(BoolExprNode)node.children[2], vars);
    if (loopType.tag == TypeEnum.ARRAY || loopType.tag == TypeEnum.STRING)
    {
        auto loopVarName = foreachArgs[0];
        auto loopVar = new VarTypePair();
        auto elemSize = 0;
        loopVar.varName = loopVarName;
        if (loopType.tag == TypeEnum.ARRAY)
        {
            loopVar.type = loopType.array.arrayType.copy;
            elemSize = loopType.array.arrayType.size;
        }
        else if (loopType.tag == TypeEnum.STRING)
        {
            auto wrap = new Type();
            wrap.tag = TypeEnum.CHAR;
            loopVar.type = wrap;
            elemSize = wrap.size;
        }
        vars.addStackVar(loopVar);
        vars.allocateStackSpace(8);
        auto arrayLoc = vars.getTop.to!string;
        vars.allocateStackSpace(8);
        auto countLoc = vars.getTop.to!string;
        scope (exit) vars.deallocateStackSpace(16);
        // The array is in r8
        // Initialize internal count variable
        str ~= "    mov    r10, -1\n";
        str ~= "    mov    qword [rbp-" ~ countLoc
                                        ~ "], r10\n";
        // Preserve the array
        str ~= "    mov    qword [rbp-" ~ arrayLoc
                                        ~ "], r8\n";
        str ~= foreachLoop ~ ":\n";
        // Restore counter and array
        str ~= "    mov    r8, qword [rbp-" ~ arrayLoc
                                            ~ "]\n";
        str ~= "    mov    r10, qword [rbp-" ~ countLoc
                                             ~ "]\n";
        str ~= "    add    r10, 1\n";
        // Set the index variable if there is one
        if (hasIndex)
        {
            // Save value in r8
            str ~= "    mov    r11, r8\n";
            // Set index value with counter value
            str ~= "    mov    r8, r10\n";
            str ~= vars.compileVarSet(indexVarName);
            // Restore value in r8
            str ~= "    mov    r8, r11\n";
        }
        // Get the array size
        str ~= "    mov    r9, qword [r8+" ~ MARK_FUNC_PTR.to!string
                                           ~ "]\n";
        str ~= "    cmp    r10, r9\n";
        str ~= "    jge    " ~ endForeach
                             ~ "\n";
        str ~= "    mov    qword [rbp-" ~ countLoc
                                        ~ "], r10\n";
        // Multiply counter by size of the array elements to get the elem offset
        str ~= "    imul   r10, " ~ elemSize.to!string
                                  ~ "\n";
        str ~= "    add    r10, " ~ (MARK_FUNC_PTR + STR_SIZE).to!string
                                  ~ "\n";
        // Actually add in the array pointer value
        str ~= "    add    r10, r8\n";
        // Zero the register if the type is less than 4 bytes
        if ((loopType.tag == TypeEnum.ARRAY &&
            loopType.array.arrayType.size < 4)
            || (loopType.tag == TypeEnum.STRING))
        {
            str ~= "    mov    r11, 0\n";
        }
        if (loopType.tag == TypeEnum.ARRAY &&
            loopType.array.arrayType.needsSignExtend)
        {
            // Get the element in r11
            str ~= "    movsx  r11, " ~ getWordSize(elemSize)
                                      ~ " [r10]\n";
        }
        else
        {
            // Get the element in r11
            str ~= "    mov    r11" ~ getRRegSuffix(elemSize)
                                    ~ ", "
                                    ~ getWordSize(elemSize)
                                    ~ " [r10]\n";
        }
        // Preserve the array
        str ~= "    mov    qword [rbp-" ~ arrayLoc
                                        ~ "], r8\n";
        // Set the loop var
        str ~= "    mov    r8, r11\n";
        str ~= vars.compileVarSet(loopVarName);
        // We're officially about to execute the block of the loop, so set
        // hasRun
        str ~= "    mov    qword [rbp-" ~ hasRun ~ "], 1\n";
        str ~= compileStatement(cast(StatementNode)node.children[3], vars);
        str ~= "    jmp    " ~ foreachLoop
                             ~ "\n";
        str ~= endForeach ~ ":\n";
    }
    else if (loopType.tag == TypeEnum.TUPLE)
    {
        // TODO After we've determined how tuples are handled, this is
        // basically just the ARRAY case but for more than one variable. Also
        // need to determine if it's a runtime error for the arrays to not all
        // be the same length, or if it just ends after the first array is
        // exhausted
    }
    vars.breakLabels.length--;
    vars.continueLabels.length--;
    // If we have an EndBlocks chain, then move hasRun into r8 and compile the
    // chain
    if (cast(EndBlocksNode)node.children[$-1])
    {
        str ~= "    mov    r8, qword [rbp-" ~ hasRun ~ "]\n";
        str ~= compileEndBlocks(
            cast(EndBlocksNode)node.children[$-1], vars
        );
    }
    return str;
}

string compileMatchStmt(MatchStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    // Allocate space for and set the hasRun value, which tracks whether the
    // if-else-if chain executed any blocks or not
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto hasRun = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ hasRun ~ "], 0\n";
    vars.matchEndBlockHasRunLabels ~= hasRun;
    scope (exit) vars.matchEndBlockHasRunLabels.length--;
    // If a match succeeds, then we have a label to jump to once the match
    // statement is executed
    vars.matchEndLabel ~= vars.getUniqLabel;
    vars.allocateStackSpace(8);
    vars.matchTypeLoc ~= vars.getTop;
    scope (exit)
    {
        vars.deallocateStackSpace(8);
        vars.matchEndLabel.length--;
        vars.matchTypeLoc.length--;
    }
    str ~= compileCondAssignments(
        cast(CondAssignmentsNode)node.children[0], vars
    );
    str ~= compileBoolExpr(cast(BoolExprNode)node.children[1], vars);
    str ~= "    mov    qword [rbp-" ~ vars.matchTypeLoc[$-1].to!string
                                    ~ "], r8\n";
    auto matchArmEndIndex = (cast(EndBlocksNode)(node.children[$-1]))
                          ? node.children.length - 1
                          : node.children.length;
    foreach (child; node.children[2..matchArmEndIndex])
    {
        str ~= compileMatchWhen(cast(MatchWhenNode)child, vars);
    }
    str ~= vars.matchEndLabel[$-1] ~ ":\n";
    if (matchArmEndIndex < node.children.length)
    {
        // hasRun may have been set when executing the match-arm block, so set
        // r8 in preparation for the end blocks
        str ~= "    mov    r8, qword [rbp-" ~ hasRun ~ "]\n";
        str ~= compileEndBlocks(cast(EndBlocksNode)node.children[$-1], vars);
    }
    return str;
}

string compileMatchWhen(MatchWhenNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    // If the match fails, then we have access to the label to jump to to try
    // the next match
    vars.matchNextWhenLabel ~= vars.getUniqLabel;
    // Inside each pattern, we test the individual components of the match.
    // If the match fails, then we put in the code to jump to the next match
    // branch
    str ~= compilePattern(cast(PatternNode)node.children[0], vars);
    if (cast(CondAssignmentsNode)node.children[1])
    {
        str ~= compileCondAssignments(
            cast(CondAssignmentsNode)node.children[1], vars
        );
        str ~= compileBoolExpr(cast(BoolExprNode)node.children[2], vars);
        // Test if the guard clause passed
        str ~= "    cmp    r8, 0\n";
        str ~= "    je     " ~ vars.matchNextWhenLabel[$-1]
                             ~ "\n";
        // We're officially about to execute the match arm block, so set hasRun
        str ~= "    mov    qword [rbp-" ~ vars.matchEndBlockHasRunLabels[$-1]
                                        ~ "], 1\n";
        str ~= compileStatement(cast(StatementNode)node.children[3], vars);
    }
    else
    {
        // We're officially about to execute the match arm block, so set hasRun
        str ~= "    mov    qword [rbp-" ~ vars.matchEndBlockHasRunLabels[$-1]
                                        ~ "], 1\n";
        str ~= compileStatement(cast(StatementNode)node.children[1], vars);
    }
    // If we got here, then the match was successful and the inner statement was
    // executed, so jump to the end of the match statement
    str ~= "    jmp    " ~ vars.matchEndLabel[$-1]
                         ~ "\n";
    str ~= vars.matchNextWhenLabel[$-1] ~ ":\n";
    vars.matchNextWhenLabel.length--;
    return str;
}

string compilePattern(PatternNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto child = node.children[0];
    if (cast(DestructVariantPatternNode)child)
        return compileDestructVariantPattern(
            cast(DestructVariantPatternNode)child, vars
        );
    else if (cast(StructPatternNode)child)
        return compileStructPattern(cast(StructPatternNode)child, vars);
    else if (cast(BoolPatternNode)child)
        return compileBoolPattern(cast(BoolPatternNode)child, vars);
    else if (cast(StringPatternNode)child)
        return compileStringPattern(cast(StringPatternNode)child, vars);
    else if (cast(CharPatternNode)child)
        return compileCharPattern(cast(CharPatternNode)child, vars);
    else if (cast(FloatPatternNode)child)
        return compileFloatPattern(cast(FloatPatternNode)child, vars);
    else if (cast(IntPatternNode)child)
        return compileIntPattern(cast(IntPatternNode)child, vars);
    else if (cast(TuplePatternNode)child)
        return compileTuplePattern(cast(TuplePatternNode)child, vars);
    else if (cast(ArrayEmptyPatternNode)child)
        return compileArrayEmptyPattern(cast(ArrayEmptyPatternNode)child, vars);
    else if (cast(ArrayPatternNode)child)
        return compileArrayPattern(cast(ArrayPatternNode)child, vars);
    else if (cast(ArrayTailPatternNode)child)
        return compileArrayTailPattern(cast(ArrayTailPatternNode)child, vars);
    else if (cast(WildcardPatternNode)child)
        return compileWildcardPattern(cast(WildcardPatternNode)child, vars);
    else if (cast(VarOrBareVariantPatternNode)child)
        return compileVarOrBareVariantPattern(
            cast(VarOrBareVariantPatternNode)child, vars
        );
    assert(false, "Unreachable");
    return "";
}

string compileDestructVariantPattern(DestructVariantPatternNode node,
                                     Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto variantDef = node.data["type"].get!(Type*).variantDef;
    auto str = "";
    auto constructor = getIdentifier(cast(IdentifierNode)node.children[0]);
    auto member = variantDef.getMember(constructor);
    auto memberTag = variantDef.getMemberIndex(constructor);
    str ~= "    mov    r8, qword [rbp-" ~ vars.matchTypeLoc[$-1]
                                              .to!string
                                        ~ "]\n";
    str ~= "    ; variant deconstruction match\n";
    str ~= "    mov    r9, qword [r8+" ~ MARK_FUNC_PTR.to!string
                                       ~ "]\n";
    str ~= "    cmp    r9, " ~ memberTag.to!string
                             ~ "\n";
    // If the tag doesn't match, jump to the next match arm
    str ~= "    jne    " ~ vars.matchNextWhenLabel[$-1]
                         ~ "\n";
    // But if it does match, then recurse on the patterns within the variant
    // pattern, if there are any
    if (node.children.length > 1)
    {
        auto memberTypes = member.constructorElems.tuple.types;
        auto memberTypeSizes = memberTypes.map!(a => a.size)
                                          .array;
        vars.allocateStackSpace(8);
        vars.matchTypeLoc ~= vars.getTop;
        scope (exit)
        {
            vars.deallocateStackSpace(8);
            vars.matchTypeLoc.length--;
        }
        foreach (i, child; node.children[1..$])
        {
            // Note that we're indexing into matchTypeLoc[$ - 2], not [$-1],
            // as we've allocated a next index for our types we pull for the
            // recursions, so our r8 from before is now behind one index
            str ~= "    mov    r8, qword [rbp-" ~ vars.matchTypeLoc[$-2]
                                                      .to!string
                                                ~ "]\n";
            auto memberOffset = memberTypeSizes.getAlignedIndexOffset(i);
            auto valueSize = memberTypeSizes[i];
            switch (valueSize)
            {
            case 16:
                assert(false, "Unimplemented");
                break;
            case 1:
            case 2:
                str ~= "    mov    r9, 0\n";
                goto case;
            case 4:
            case 8:
            default:
                // Get the value and put it in the top of the match type
                // "stack"
                str ~= "    mov    r9" ~ getRRegSuffix(valueSize)
                                       ~ ", "
                                       ~ getWordSize(valueSize)
                                       ~ " [r8+"
                                       ~ (MARK_FUNC_PTR
                                        + VARIANT_TAG_SIZE
                                        + memberOffset).to!string
                                       ~ "]\n";
                str ~= "    mov    qword [rbp-"
                    ~ vars.matchTypeLoc[$-1].to!string
                    ~ "], r9\n";
                str ~= compilePattern(cast(PatternNode)child, vars);
                break;
            }
        }
    }
    return str;
}

string compileStructPattern(StructPatternNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto structType = node.data["type"].get!(Type*);
    auto str = "";
    auto startIndex = 0;
    if (cast(IdentifierNode)node.children[1])
    {
        startIndex++;
    }
    vars.allocateStackSpace(8);
    vars.matchTypeLoc ~= vars.getTop;
    scope (exit)
    {
        vars.deallocateStackSpace(8);
        vars.matchTypeLoc.length--;
    }
    for (auto i = startIndex; i < node.children.length; i += 2)
    {
        auto id = getIdentifier(cast(IdentifierNode)node.children[i]);
        auto member = structType.structDef
                                .getMember(id);
        auto memberOffset = structType.structDef
                                      .getOffsetOfMember(id);
        auto memberSize = member.type.size;
        // Note that it's $-2, because of the above allocation
        str ~= "    mov    r8, qword [rbp-" ~ vars.matchTypeLoc[$-2].to!string
                                            ~ "]\n";
        // r8 is now a pointer to the beginning of the member of the struct
        str ~= "    add    r8, " ~ (MARK_FUNC_PTR
                                  + STRUCT_BUFFER_SIZE
                                  + memberOffset).to!string
                                 ~ "\n";
        switch (memberSize)
        {
        case 16:
            assert(false, "Unimplemented");
            break;
        case 1:
        case 2:
            // If it's not an 8-byte or 4-byte mov, we need to zero the target
            // register
            str ~= "    mov    r9, 0\n";
            goto case;
        case 4:
        case 8:
        default:
            str ~= "    mov    r9" ~ getRRegSuffix(memberSize)
                                   ~ ", "
                                   ~ getWordSize(memberSize)
                                   ~ "[r8]\n";
            str ~= "    mov    qword [rbp-"
                ~ vars.matchTypeLoc[$-1].to!string
                ~ "], r9\n";
            str ~= compilePattern(cast(PatternNode)node.children[i+1], vars);
            break;
        }
    }
    return str;
}

string compileBoolPattern(BoolPatternNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    str ~= "    mov    r8, qword [rbp-" ~ vars.matchTypeLoc[$-1].to!string
                                        ~ "]\n";
    auto boolVal = (cast(ASTTerminal)node.children[0])
                                     .token;
    if (boolVal == "true")
    {
        str ~= "    cmp    r8, 1\n";
    }
    else
    {
        str ~= "    cmp    r8, 0\n";
    }
    str ~= "    jne    " ~ vars.matchNextWhenLabel[$-1]
                         ~ "\n";
    return str;
}

string compileStringPattern(StringPatternNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    vars.runtimeExterns["strcmp"] = true;
    auto str = "";
    str ~= compileStringLit(cast(StringLitNode)node.children[0], vars);
    str ~= "    mov    r9, qword [rbp-" ~ vars.matchTypeLoc[$-1].to!string
                                        ~ "]\n";
    // Strings to compare are in r8 and r9 Increment pointers to point at the
    // beginning of the string data, skipping runtime data and string length.
    // Since these strings are null-terminated, we can just call strcmp
    str ~= "    add    r8, " ~ (MARK_FUNC_PTR + STR_SIZE).to!string
                             ~ "\n";
    str ~= "    add    r9, " ~ (MARK_FUNC_PTR + STR_SIZE).to!string
                             ~ "\n";
    str ~= "    mov    rdi, r9\n";
    str ~= "    mov    rsi, r8\n";
    str ~= "    call   strcmp\n";
    // strcmp returns an int, so the value we care about is in eax, not rax
    str ~= "    cmp    eax, 0\n";
    str ~= "    jne     " ~ vars.matchNextWhenLabel[$-1]
                          ~ "\n";
    return str;
}

string compileCharPattern(CharPatternNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    str ~= "    mov    r8, qword [rbp-" ~ vars.matchTypeLoc[$-1].to!string
                                        ~ "]\n";
    // Char range
    if (node.children.length > 1)
    {
        auto charOne = (cast(ASTTerminal)
                       (cast(CharLitNode)node.children[0])
                                             .children[0]).token[1..$-1]
                                                          .getChar;
        auto charTwo = (cast(ASTTerminal)
                       (cast(CharLitNode)node.children[1])
                                             .children[0]).token[1..$-1]
                                                          .getChar;
        str ~= "    cmp    r8, " ~ charOne.to!uint.to!string
                                 ~ "\n";
        str ~= "    jl     " ~ vars.matchNextWhenLabel[$-1]
                             ~ "\n";
        str ~= "    cmp    r8, " ~ charTwo.to!uint.to!string
                                 ~ "\n";
        str ~= "    jg     " ~ vars.matchNextWhenLabel[$-1]
                             ~ "\n";
    }
    // Single char
    else
    {
        auto charOne = (cast(ASTTerminal)
                       (cast(CharLitNode)node.children[0])
                                             .children[0]).token[1..$-1]
                                                          .getChar;
        str ~= "    cmp    r8, " ~ charOne.to!uint.to!string
                                 ~ "\n";
        str ~= "    jne    " ~ vars.matchNextWhenLabel[$-1]
                             ~ "\n";
    }
    return str;
}

string compileFloatPattern(FloatPatternNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    assert(false, "Unimplemented");
    return "";
}

string compileIntPattern(IntPatternNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto type = node.data["type"].get!(Type*);
    auto str = "";
    str ~= "    mov    r8, qword [rbp-" ~ vars.matchTypeLoc[$-1].to!string
                                        ~ "]\n";
    if (type.needsSignExtend)
    {
        str ~= "    movsx    r8, r8" ~ getRRegSuffix(type.size)
                                     ~ "\n";
    }
    // Int range
    if (node.children.length > 1)
    {
        auto intOne = (cast(ASTTerminal)
                       (cast(IntNumNode)node.children[0])
                                             .children[0]).token
                                                          .to!int;
        auto intTwo = (cast(ASTTerminal)
                       (cast(IntNumNode)node.children[1])
                                             .children[0]).token
                                                          .to!int;
        str ~= "    cmp    r8, " ~ intOne.to!int.to!string
                                 ~ "\n";
        str ~= "    jl     " ~ vars.matchNextWhenLabel[$-1]
                             ~ "\n";
        str ~= "    cmp    r8, " ~ intTwo.to!int.to!string
                                 ~ "\n";
        str ~= "    jg     " ~ vars.matchNextWhenLabel[$-1]
                             ~ "\n";
    }
    // Single int
    else
    {
        auto intOne = (cast(ASTTerminal)
                       (cast(IntNumNode)node.children[0])
                                             .children[0]).token
                                                          .to!int;
        str ~= "    cmp    r8, " ~ intOne.to!int.to!string
                                 ~ "\n";
        str ~= "    jne    " ~ vars.matchNextWhenLabel[$-1]
                             ~ "\n";
    }
    return str;
}

string compileTuplePattern(TuplePatternNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto tupleType = node.data["type"].get!(Type*).tuple;
    auto str = "";
    vars.allocateStackSpace(8);
    vars.matchTypeLoc ~= vars.getTop;
    scope (exit)
    {
        vars.deallocateStackSpace(8);
        vars.matchTypeLoc.length--;
    }
    foreach (i, child; node.children)
    {
        auto valueOffset = tupleType.getOffsetOfValue(i);
        auto valueSize = tupleType.types[i].size;
        // Note that it's $-2, because of the above allocation
        str ~= "    mov    r8, qword [rbp-" ~ vars.matchTypeLoc[$-2].to!string
                                            ~ "]\n";
        // r8 is being set to a pointer to the i'th value in the tuple
        str ~= "    add    r8, " ~ (MARK_FUNC_PTR
                                  + STRUCT_BUFFER_SIZE
                                  + valueOffset).to!string
                                 ~ "\n";
        switch (valueSize)
        {
        case 1:
        case 2:
            // If it's not an 8-byte or 4-byte mov, we need to zero the target
            // register
            str ~= "    mov    r9, 0\n";
            goto case;
        case 4:
        case 8:
        default:
            str ~= "    mov    r9" ~ getRRegSuffix(valueSize)
                                   ~ ", "
                                   ~ getWordSize(valueSize)
                                   ~ "[r8]\n";
            str ~= "    mov    qword [rbp-"
                ~ vars.matchTypeLoc[$-1].to!string
                ~ "], r9\n";
            str ~= compilePattern(cast(PatternNode)child, vars);
            break;
        }
    }
    return str;
}

string compileArrayEmptyPattern(ArrayEmptyPatternNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    str ~= "    mov    r8, qword [rbp-" ~ vars.matchTypeLoc[$-1].to!string
                                        ~ "]\n";
    // Get array length
    str ~= "    mov    r9, qword [r8+" ~ MARK_FUNC_PTR.to!string
                                       ~ "]\n";
    str ~= "    cmp    r9, 0\n";
    str ~= "    jne    " ~ vars.matchNextWhenLabel[$-1]
                         ~ "\n";
    return str;
}

string compileArrayPattern(ArrayPatternNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto type = node.data["type"].get!(Type*);
    auto str = "";
    str ~= "    mov    r8, qword [rbp-" ~ vars.matchTypeLoc[$-1].to!string
                                        ~ "]\n";
    auto endIndex = node.children.length;
    auto tailId = "";
    if (cast(IdentifierNode)node.children[$-1])
    {
        // Move back before the ".." token
        endIndex = endIndex - 2;
        tailId = getIdentifier(cast(IdentifierNode)node.children[$-1]);
    }
    else if (cast(ASTTerminal)node.children[$-1])
    {
        // Move back before the ".." token
        endIndex = endIndex - 1;
    }
    auto length = endIndex;
    // Get array length
    str ~= "    mov    r9, qword [r8+" ~ MARK_FUNC_PTR.to!string
                                       ~ "]\n";
    str ~= "    cmp    r9, " ~ length.to!string
                             ~ "\n";
    // In this case, we're matching against an exact array length
    if (endIndex == node.children.length)
    {
        str ~= "    jne    " ~ vars.matchNextWhenLabel[$-1]
                             ~ "\n";
    }
    // In this case, we simply need at least a certain length
    else
    {
        str ~= "    jl     " ~ vars.matchNextWhenLabel[$-1]
                             ~ "\n";
    }
    vars.allocateStackSpace(8);
    vars.matchTypeLoc ~= vars.getTop;
    scope (exit)
    {
        vars.deallocateStackSpace(8);
        vars.matchTypeLoc.length--;
    }
    auto valueSize = 0;
    if (type.tag == TypeEnum.ARRAY)
    {
        valueSize = type.array.arrayType.size;
    }
    else if (type.tag == TypeEnum.STRING)
    {
        auto charType = new Type();
        charType.tag = TypeEnum.CHAR;
        valueSize = charType.size;
    }
    foreach (i, child; node.children[0..endIndex])
    {
        // Note that we're indexing into matchTypeLoc[$ - 2], not [$-1],
        // as we've allocated a next index for our types we pull for the
        // recursions, so our r8 from before is now behind one index
        str ~= "    mov    r8, qword [rbp-" ~ vars.matchTypeLoc[$-2]
                                                  .to!string
                                            ~ "]\n";
        auto memberOffset = i * valueSize;
        switch (valueSize)
        {
        case 16:
            assert(false, "Unimplemented");
            break;
        case 1:
        case 2:
            str ~= "    mov    r9, 0\n";
            goto case;
        case 4:
        case 8:
        default:
            // Get the value and put it in the top of the match type
            // "stack"
            str ~= "    mov    r9" ~ getRRegSuffix(valueSize)
                                   ~ ", "
                                   ~ getWordSize(valueSize)
                                   ~ " [r8+"
                                   ~ (MARK_FUNC_PTR
                                    + STR_SIZE
                                    + memberOffset).to!string
                                   ~ "]\n";
            str ~= "    mov    qword [rbp-"
                ~ vars.matchTypeLoc[$-1].to!string
                ~ "], r9\n";
            str ~= compilePattern(cast(PatternNode)child, vars);
            break;
        }
    }
    // In this case, we need to make a copy of the tail of the array and make
    // it available as a variable with name tailId in the match arm statement.
    // Note that we only do this if the match was actually successful up to
    // this point
    if (tailId != "")
    {
        assert(false, "Unimplemented");
    }
    return str;
}

string compileArrayTailPattern(ArrayTailPatternNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto type = node.data["type"].get!(Type*);
    auto str = "";
    str ~= "    mov    r8, qword [rbp-" ~ vars.matchTypeLoc[$-1].to!string
                                        ~ "]\n";
    auto startIndex = 0;
    auto headId = "";
    if (cast(IdentifierNode)node.children[0])
    {
        // Move beyond the headId node
        startIndex++;
        // Grab the headId token
        headId = getIdentifier(cast(IdentifierNode)node.children[0]);
    }
    // Get array length
    str ~= "    mov    r9, qword [r8+" ~ MARK_FUNC_PTR.to!string
                                       ~ "]\n";
    // Determine if there are enough elements in the array to compare against
    // every node in the array match
    str ~= "    cmp    r9, " ~ (node.children.length - startIndex).to!string
                             ~ "\n";
    // If there aren't enough elements in the array, fail the match
    str ~= "    jl     " ~ vars.matchNextWhenLabel[$-1]
                         ~ "\n";
    vars.allocateStackSpace(8);
    vars.matchTypeLoc ~= vars.getTop;
    vars.allocateStackSpace(8);
    auto arrayStartIndex = vars.getTop;
    scope (exit)
    {
        vars.deallocateStackSpace(16);
        vars.matchTypeLoc.length--;
    }
    auto valueSize = 0;
    if (type.tag == TypeEnum.ARRAY)
    {
        valueSize = type.array.arrayType.size;
    }
    else if (type.tag == TypeEnum.STRING)
    {
        auto charType = new Type();
        charType.tag = TypeEnum.CHAR;
        valueSize = charType.size;
    }
    str ~= "    sub    r9, " ~ (node.children.length - startIndex).to!string
                             ~ "\n";
    str ~= "    imul   r9, " ~ valueSize.to!string
                             ~ "\n";
    str ~= "    mov    qword [rbp-" ~ arrayStartIndex.to!string
                                    ~ "], r9\n";
    foreach (i, child; node.children[startIndex..$])
    {
        // Note that we're indexing into matchTypeLoc[$ - 2], not [$-1],
        // as we've allocated a next index for our types we pull for the
        // recursions, so our r8 from before is now behind one index
        str ~= "    mov    r8, qword [rbp-" ~ vars.matchTypeLoc[$-2]
                                                  .to!string
                                            ~ "]\n";
        str ~= "    mov    r9, qword [rbp-" ~ arrayStartIndex.to!string
                                            ~ "]\n";
        str ~= "    add    r9, " ~ (i * valueSize).to!string
                                 ~ "\n";
        switch (valueSize)
        {
        case 16:
            assert(false, "Unimplemented");
            break;
        case 1:
        case 2:
            str ~= "    mov    r9, 0\n";
            goto case;
        case 4:
        case 8:
        default:
            str ~= "    add    r8, " ~ (MARK_FUNC_PTR
                                      + STR_SIZE).to!string
                                     ~ "\n";
            str ~= "    add    r8, r9\n";
            // Get the value and put it in the top of the match type
            // "stack"
            str ~= "    mov    r9" ~ getRRegSuffix(valueSize)
                                   ~ ", "
                                   ~ getWordSize(valueSize)
                                   ~ " [r8]\n";
            str ~= "    mov    qword [rbp-"
                ~ vars.matchTypeLoc[$-1].to!string
                ~ "], r9\n";
            str ~= compilePattern(cast(PatternNode)child, vars);
            break;
        }
    }
    // In this case, we need to make a copy of the tail of the array and make
    // it available as a variable with name headId in the match arm statement.
    // Note that we only do this if the match was actually successful up to
    // this point
    if (headId != "")
    {
        assert(false, "Unimplemented");
    }
    return str;
}

string compileWildcardPattern(WildcardPatternNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    // No-op
    return "";
}

string compileVarOrBareVariantPattern(VarOrBareVariantPatternNode node,
                                      Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto type = node.data["type"].get!(Type*);
    auto name = getIdentifier(cast(IdentifierNode)node.children[0]);
    auto str = "";
    str ~= "    mov    r8, qword [rbp-" ~ vars.matchTypeLoc[$-1].to!string
                                        ~ "]\n";
    // Empty constructor match
    if (type.tag == TypeEnum.VARIANT && type.variantDef.isMember(name))
    {
        str ~= "    ; Bare variant match\n";
        auto memberTag = type.variantDef.getMemberIndex(name);
        str ~= "    mov    r9, qword [r8+" ~ MARK_FUNC_PTR.to!string
                                           ~ "]\n";
        str ~= "    cmp    r9, " ~ memberTag.to!string
                                 ~ "\n";
        // If the tag doesn't match, jump to the next match arm
        str ~= "    jne    " ~ vars.matchNextWhenLabel[$-1]
                             ~ "\n";
    }
    // Variable binding
    else
    {
        str ~= "    ; variable binding\n";
        auto var = new VarTypePair;
        var.varName = name;
        var.type = type;
        vars.addStackVar(var);
        str ~= vars.compileVarSet(name);
    }
    return str;
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
    assert(false, "Unreachable");
    return "";
}

string compileDeclTypeInfer(DeclTypeInferNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto left = node.children[0];
    auto right = node.children[1];
    auto str = "";
    auto type = right.data["type"].get!(Type*);
    if (cast(IdentifierNode)left)
    {
        str ~= compileExpression(cast(BoolExprNode)right, vars);
        auto varName = getIdentifier(cast(IdentifierNode)left);
        auto var = new VarTypePair;
        var.varName = varName;
        var.type = type;
        vars.addStackVar(var);
        // Note the use of str in the expression, which is why we're not ~=ing
        str = "    ; var infer assign [" ~ varName
                                         ~ "]\n"
                                         ~ str
                                         ~ vars.compileVarSet(varName);
    }
    else
    {
        auto idNodes = (cast(IdTupleNode)left).children;
        auto types = right.data["type"]
                          .get!(Type*)
                          .tuple
                          .types;
        auto sizes = types.map!(a => a.size)
                          .array;
        string[] identifiers;
        foreach (child; idNodes)
        {
            identifiers ~= getIdentifier(cast(IdentifierNode)child);
        }
        str ~= compileExpression(cast(BoolExprNode)right, vars);
        str ~= "    mov    r10, r8\n";
        foreach (i, ident, type; lockstep(identifiers, types))
        {
            auto alignedIndex = sizes.getAlignedIndexOffset(i);
            auto size = sizes[i];
            str ~= "    mov    r8" ~ getRRegSuffix(size)
                                   ~ ", "
                                   ~ getWordSize(size)
                                   ~ " [r10+"
                                   ~ (MARK_FUNC_PTR
                                    + STRUCT_BUFFER_SIZE
                                    + alignedIndex).to!string
                                   ~ "]"
                                   ~ "\n";
            auto var = new VarTypePair;
            var.varName = ident;
            var.type = type;
            vars.addStackVar(var);
            str ~= vars.compileVarSet(ident);
        }
    }
    return str;
}

string compileVariableTypePair(VariableTypePairNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    auto pair = node.data["pair"].get!(VarTypePair*);
    vars.addStackVar(pair);
    final switch (pair.type.tag)
    {
    case TypeEnum.STRING:
        str ~= "    ; allocate empty string\n";
        str ~= "    mov    rdi, " ~ (MARK_FUNC_PTR
                                   + STR_SIZE).to!string
                                  ~ "\n";
        str ~= compileGetGCEnv("rsi", vars);
        str ~= "    call   __GC_malloc\n";
        vars.runtimeExterns["__mellow_GC_mark_S"] = true;
        // Set the marking function for string allocations
        str ~= "    mov    qword [rax], __mellow_GC_mark_S\n";
        // Set the length of the string, where the string size location is just
        // past the runtime data
        str ~= "    mov    qword [rax+" ~ MARK_FUNC_PTR.to!string
                                        ~ "], 0\n";
        // The string value ptr sits in r8
        str ~= "    mov    r8, rax\n";
        break;
    case TypeEnum.SET:
        assert(false, "Unimplemented");
        break;
    case TypeEnum.HASH:
        assert(false, "Unimplemented");
        break;
    case TypeEnum.ARRAY:
        auto type = pair.type;
        auto elemSize = type.array.arrayType.size;
        auto typeIdNode = cast(TypeIdNode)node.children[1];
        auto arrayTypeNode = cast(ArrayTypeNode)typeIdNode.children[0];
        if (arrayTypeNode.children.length > 1)
        {
            auto allocBoolExpr = cast(BoolExprNode)arrayTypeNode.children[0];
            str ~= compileBoolExpr(allocBoolExpr, vars);
            vars.allocateStackSpace(8);
            scope (exit) vars.deallocateStackSpace(8);
            auto arrayLenLoc = vars.getTop.to!string;
            str ~= "    mov    qword [rbp-" ~ arrayLenLoc ~ "], r8\n";
            str ~= "    mov    rdi, r8\n";
            str ~= "    imul   rdi, " ~ elemSize.to!string ~ "\n";
            str ~= "    add    rdi, " ~ (MARK_FUNC_PTR + STR_SIZE).to!string
                                      ~ "\n";
            str ~= compileGetGCEnv("rsi", vars);
            str ~= "    call   __GC_malloc\n";
            // Populate marking function
            vars.runtimeExterns[type.formatMarkFuncName] = true;
            str ~= "    mov    qword [rax], " ~ type.formatMarkFuncName
                                              ~ "\n";
            // Retrive the array length value
            str ~= "    mov    r8, qword [rbp-" ~ arrayLenLoc ~ "]\n";
            // Set array length to number of elements
            str ~= "    mov    qword [rax+" ~ MARK_FUNC_PTR.to!string
                                            ~ "], r8\n";
            str ~= "    mov    r8, rax\n";
        }
        else
        {
            str ~= "    mov    rdi, " ~ (MARK_FUNC_PTR + STR_SIZE).to!string
                                      ~ "\n";
            str ~= compileGetGCEnv("rsi", vars);
            str ~= "    call   __GC_malloc\n";
            // Populate marking function
            vars.runtimeExterns[type.formatMarkFuncName] = true;
            str ~= "    mov    qword [rax], " ~ type.formatMarkFuncName
                                              ~ "\n";
            str ~= "    mov    qword [rax+" ~ MARK_FUNC_PTR.to!string
                                            ~ "], 0\n";
            str ~= "    mov    r8, rax\n";
        }
        break;
    case TypeEnum.FUNCPTR:
        assert(false, "Unimplemented");
        break;
    case TypeEnum.STRUCT:
        assert(false, "Unimplemented");
        break;
    case TypeEnum.VARIANT:
        assert(false, "Unimplemented");
        break;
    case TypeEnum.CHAN:
        vars.runtimeExterns["__mellow_get_chan_mutex_index"] = true;
        auto elemSize = pair.type.chan.chanType.size;
        auto totalAllocSize = MARK_FUNC_PTR
                            + CHAN_VALID_SIZE
                            + elemSize;
        str ~= "    mov    rdi, " ~ totalAllocSize.to!string
                                  ~ "\n";
        // TODO: Channels must be allocated on a non-GC'd heap, as they act as
        // communication methods between green threads which each have their
        // own, separate, GC'd heaps. This probably implies that channels will
        // need to be ref-counted
        str ~= "    call   malloc\n";
        vars.allocateStackSpace(8);
        scope (exit) vars.deallocateStackSpace(8);
        auto chanLoc = vars.getTop.to!string;
        str ~= "    mov    qword [rbp-" ~ chanLoc ~ "], rax\n";
        str ~= "    call   __mellow_get_chan_mutex_index\n";
        str ~= "    shl    rax, 16\n";
        str ~= "    mov    r8, qword [rbp-" ~ chanLoc ~ "]\n";
        str ~= "    mov    qword [r8+" ~ MARK_FUNC_PTR.to!string ~ "], 0\n";
        str ~= "    or     qword [r8+" ~ MARK_FUNC_PTR.to!string ~ "], rax\n";
        // Set chan valid-element segment to false
        str ~= "    mov    r12, 0xFFFFFFFFFFFFFFFE\n";
        str ~= "    and    qword [r8+" ~ MARK_FUNC_PTR.to!string ~ "], r12\n";
        break;
    case TypeEnum.LONG:
    case TypeEnum.INT:
    case TypeEnum.SHORT:
    case TypeEnum.BYTE:
    case TypeEnum.CHAR:
    case TypeEnum.BOOL:
        str ~= "    mov    r8, 0\n";
        break;
    case TypeEnum.FLOAT:
    case TypeEnum.DOUBLE:
        assert(false, "Unimplemented");
        break;
    case TypeEnum.TUPLE:
    case TypeEnum.AGGREGATE:
    case TypeEnum.VOID:
        assert(false, "Unimplemented");
        break;
    }
    str ~= vars.compileVarSet(pair.varName);
    return str;
}

string compileAssignExisting(AssignExistingNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    auto op = (cast(ASTTerminal)node.children[1]).token;
    auto leftType = node.children[0].data["type"].get!(Type*);
    auto rightType = node.children[2].data["type"].get!(Type*);
    str ~= compileBoolExpr(cast(BoolExprNode)node.children[2], vars);
    vars.allocateStackSpace(8);
    auto valLoc = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ valLoc ~ "], r8\n";
    // Assume it's true to begin with
    vars.isStackAligned = true;
    str ~= compileLorRValue(cast(LorRValueNode)node.children[0], vars);
    str ~= "    mov    r9, qword [rbp-" ~ valLoc ~ "]\n";
    // The pointer to the LHS memory is in r8, and the RHS value is in r9
    vars.deallocateStackSpace(8);
    final switch (op)
    {
    case "=":
        if (vars.isStackAligned)
        {
            str ~= "    mov    qword [r8], r9\n";
        }
        else
        {
            str ~= "    mov    " ~ getWordSize(rightType.size)
                                 ~ " [r8], r9"
                                 ~ getRRegSuffix(rightType.size) ~ "\n";
        }
        break;
    case "+=":
        str ~= "    mov    r11, 0\n";
        if (vars.isStackAligned)
        {
            str ~= "    mov    r11, qword [r8]\n";
            str ~= "    add    r11, r9\n";
            str ~= "    mov    qword [r8], r11\n";
        }
        else
        {
            str ~= "    mov    r11" ~ rightType.size.getRRegSuffix
                                    ~ ", "
                                    ~ rightType.size.getWordSize
                                    ~ "[r8]\n";
            str ~= "    add    r11, r9\n";
            str ~= "    mov    " ~ rightType.size.getWordSize
                                 ~ " [r8], r11"
                                 ~ rightType.size.getRRegSuffix
                                 ~ "\n";
        }
        break;
    case "-=":
        str ~= "    mov    r11, 0\n";
        if (vars.isStackAligned)
        {
            str ~= "    mov    r11, qword [r8]\n";
            str ~= "    sub    r11, r9\n";
            str ~= "    mov    qword [r8], r11\n";
        }
        else
        {
            str ~= "    mov    r11" ~ rightType.size.getRRegSuffix
                                    ~ ", "
                                    ~ rightType.size.getWordSize
                                    ~ "[r8]\n";
            str ~= "    sub    r11, r9\n";
            str ~= "    mov    " ~ rightType.size.getWordSize
                                 ~ " [r8], r11"
                                 ~ rightType.size.getRRegSuffix
                                 ~ "\n";
        }
        break;
    case "*=":
        str ~= "    mov    r11, 0\n";
        if (vars.isStackAligned)
        {
            str ~= "    mov    r11, qword [r8]\n";
            str ~= "    imul   r11, r9\n";
            str ~= "    mov    qword [r8], r11\n";
        }
        else
        {
            str ~= "    mov    r11" ~ rightType.size.getRRegSuffix
                                    ~ ", "
                                    ~ rightType.size.getWordSize
                                    ~ "[r8]\n";
            str ~= "    imul   r11, r9\n";
            str ~= "    mov    " ~ rightType.size.getWordSize
                                 ~ " [r8], r11"
                                 ~ rightType.size.getRRegSuffix
                                 ~ "\n";
        }
        break;
    case "/=":
        str ~= "    mov    r11, 0\n";
        if (vars.isStackAligned)
        {
            str ~= "    mov    r11, qword [r8]\n";
            str ~= "    mov    rax, r11\n";
            // Sign extend rax into rdx, to get rdx:rax
            str ~= "    cqo\n";
            str ~= "    idiv   r9\n";
            // Result of divison lies in rax
            str ~= "    mov    r11, rax\n";
            str ~= "    mov    qword [r8], r11\n";
        }
        else
        {
            str ~= "    mov    r11" ~ rightType.size.getRRegSuffix
                                    ~ ", "
                                    ~ rightType.size.getWordSize
                                    ~ "[r8]\n";
            str ~= "    mov    rax, r11\n";
            // Sign extend rax into rdx, to get rdx:rax
            str ~= "    cqo\n";
            str ~= "    idiv   r9\n";
            // Result of divison lies in rax
            str ~= "    mov    r11, rax\n";
            str ~= "    mov    " ~ rightType.size.getWordSize
                                 ~ " [r8], r11"
                                 ~ rightType.size.getRRegSuffix
                                 ~ "\n";
        }
        break;
    case "%=":
        str ~= "    mov    r11, 0\n";
        if (vars.isStackAligned)
        {
            str ~= "    mov    r11, qword [r8]\n";
            str ~= "    mov    rax, r11\n";
            // Sign extend rax into rdx, to get rdx:rax
            str ~= "    cqo\n";
            str ~= "    idiv   r9\n";
            // Remainder lies in rax
            str ~= "    mov    r11, rdx\n";
            str ~= "    mov    qword [r8], r11\n";
        }
        else
        {
            str ~= "    mov    r11" ~ rightType.size.getRRegSuffix
                                    ~ ", "
                                    ~ rightType.size.getWordSize
                                    ~ "[r8]\n";
            str ~= "    mov    rax, r11\n";
            // Sign extend rax into rdx, to get rdx:rax
            str ~= "    cqo\n";
            str ~= "    idiv   r9\n";
            // Remainder lies in rdx
            str ~= "    mov    r11, rdx\n";
            str ~= "    mov    " ~ rightType.size.getWordSize
                                 ~ " [r8], r11"
                                 ~ rightType.size.getRRegSuffix
                                 ~ "\n";
        }
        break;
    case "~=":
        str ~= compileAppendEquals(leftType, rightType, vars);
        break;
    }
    return str;
}

// The _address_ of the pointer is in r8, and the new element is in r9
string compileAppendEquals(Type* leftType, Type* rightType, Context* vars)
{
    // The address of the LHS pointer is in r8, and the elem is in r9

    vars.runtimeExterns["__arr_arr_append"] = true;
    vars.runtimeExterns["__arr_elem_append"] = true;

    auto str = "";

    // Store the address of the LHS pointer, to store into later
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto lhsLoc = vars.getTop.to!string;

    str ~= "    mov    qword [rbp-" ~ lhsLoc ~ "], r8\n";
    // Call the array-elem append routine, and place that result back into the
    // memory location for the LHS
    //
    // First, get the value of the LHS in rdi
    str ~= "    mov    rdi, qword [r8]\n";
    // Then, the elem value
    str ~= "    mov    rsi, r9\n";

    if (leftType.tag == TypeEnum.STRING)
    {
        // Is a string append
        str ~= "    mov    rcx, 1\n";
        // The size of the elements in this array
        str ~= "    mov    rdx, " ~ char.sizeof.to!string ~ "\n";

        if (leftType.cmp(rightType))
        {
            // Perform the append! Result in rax
            str ~= "    call   __arr_arr_append\n";
        }
        else
        {
            // Perform the append! Result in rax
            str ~= "    call   __arr_elem_append\n";
        }
    }
    else
    {
        // Not a string append
        str ~= "    mov    rcx, 0\n";

        if (leftType.cmp(rightType))
        {
            // The size of the elements in this array
            str ~= "    mov    rdx, "
                ~ rightType.array.arrayType.size.to!string ~ "\n";
            // Perform the append! Result in rax
            str ~= "    call   __arr_arr_append\n";
        }
        else
        {
            // The size of the elements in this array
            str ~= "    mov    rdx, " ~ rightType.size.to!string ~ "\n";
            // Perform the append! Result in rax
            str ~= "    call   __arr_elem_append\n";
        }
    }

    // Set the result back into the place the LHS is stored
    str ~= "    mov    r8, qword [rbp-" ~ lhsLoc ~ "]\n";
    str ~= "    mov    qword [r8], rax\n";

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
    auto type = node.data["type"].get!(Type*);
    auto parentType = node.data["parenttype"].get!(Type*);
    auto str = "";
    vars.allocateStackSpace(8);
    auto valLoc = vars.getTop.to!string;
    scope (exit) vars.deallocateStackSpace(8);
    str ~= "    mov    qword [rbp-" ~ valLoc ~ "], r8\n";
    auto child = node.children[0];
    if (cast(IdentifierNode)child) {
        auto memberName = getIdentifier(cast(IdentifierNode)child);
        auto memberOffset = parentType.structDef
                                      .getOffsetOfMember(memberName);
        str ~= "    ; l-value dot access  on type [" ~ parentType.format
                                                     ~ "]: "
                                                     ~ memberName
                                                     ~ "\n";
        // Get the struct pointer. Since this is an L-or-R-value calculation,
        // and UFCS is not allowed syntactically, then the only thing that can
        // be doing a dot access is a pointer with elements.
        str ~= "    mov    r8, qword [r8]\n";
        // r8 is now a pointer to the beginning of the member of the struct
        str ~= "    add    r8, " ~ (MARK_FUNC_PTR
                                  + STRUCT_BUFFER_SIZE
                                  + memberOffset).to!string
                                 ~ "\n";
        if (node.children.length > 1)
        {
            str ~= compileLorRTrailer(
                cast(LorRTrailerNode)node.children[1],
                vars
            );
        }
    }
    else if (cast(SingleIndexNode)child) {

        // TODO this doesn't hold up to recursive array accesses. An array
        // index access inside of an array index access will overwrite the
        // length sentinel for the parent access, and then it will be invalid
        // for the rest of the calculation once the inner access is exited.
        // As in: arr[$-arr2[$-1]+$/2], the second arr $ (the third $ overall)
        // is now invalid

        // Populate length sentinel
        str ~= "    mov    r9, [r8]\n";
        str ~= "    mov    r11, qword [r9+" ~ MARK_FUNC_PTR.to!string
                                            ~ "]\n";
        str ~= "    mov    qword [__ZZlengthSentinel], r11\n";
        str ~= compileSingleIndex(cast(SingleIndexNode)child, vars);
        str ~= "    mov    r9, qword [rbp-" ~ valLoc ~ "]\n";
        if (!vars.release)
        {
            str ~= "    mov    r11, [r9]\n";
            str ~= "    mov    r11, qword [r11+" ~ MARK_FUNC_PTR.to!string
                                                 ~ "]\n";
            vars.runtimeExterns["printf"] = true;
            // Now, compare the array size to the index value
            auto inBoundsLabel = vars.getUniqLabel;
            str ~= "    cmp    r11, r8\n";
            // If we're within bounds, jump to continuing with the access...
            str ~= "    jg     " ~ inBoundsLabel ~ "\n";
            // Otherwise, print an assert error and hard exit!
            auto assertLabel = vars.getUniqDataLabel();
            auto entry = new DataEntry();
            entry.label = assertLabel;
            entry.data = DataEntry.toNasmDataString(
                "Assert Error: Array index out-of-bounds: " ~ errorHeader(node)
                                                            ~ "\\n"
            );
            vars.dataEntries ~= entry;
            str ~= "    mov    rdi, " ~ assertLabel ~ "\n";
            str ~= "    call   printf\n";
            str ~= "    mov    rdi, 1\n";
            str ~= "    call   exit\n";
            str ~= inBoundsLabel ~ ":\n";
        }
        // [r9] is the actual variable we're indexing, so
        // [r9]+(header offset + r8 * type.size) is the address we want
        str ~= "    mov    r9, [r9]\n";
        // Add offset for runtime data and array length
        str ~= "    add    r9, " ~ (MARK_FUNC_PTR + STR_SIZE).to!string
                                 ~ "\n";
        // Get index offset
        str ~= "    imul   r8, " ~ type.size.to!string ~ "\n";
        // Get completed address in r8
        str ~= "    add    r8, r9\n";
        if (node.children.length > 1)
        {
            str ~= compileLorRTrailer(
                cast(LorRTrailerNode)node.children[1],
                vars
            );
        }
    }
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
    auto str = "";
    if (cast(AssignmentNode)node.children[0])
    {
        str ~= compileAssignment(cast(AssignmentNode)node.children[0], vars);
    }
    else if (cast(VariableTypePairNode)node.children[0]) {
        str ~= compileVariableTypePair(
            cast(VariableTypePairNode)node.children[0], vars
        );
    }
    return str;
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
    auto left = node.children[0];
    auto right = node.children[1];
    auto str = "";
    auto type = right.data["type"].get!(Type*);
    if (cast(VariableTypePairNode)left)
    {
        str ~= compileExpression(cast(BoolExprNode)right, vars);
        auto varName = getIdentifier(
            cast(IdentifierNode)((cast(VariableTypePairNode)left).children[0])
        );
        auto var = new VarTypePair;
        var.varName = varName;
        var.type = type;
        vars.addStackVar(var);
        // Note the use of str in the expression, which is why we're not ~=ing
        str = "    ; var infer assign [" ~ varName
                                         ~ "]\n"
                                         ~ str
                                         ~ vars.compileVarSet(varName);
    }
    else
    {
        auto identifiers = (cast(VariableTypePairTupleNode)left)
                           .children
                           .map!(a => (cast(VariableTypePairNode)a).children[0])
                           .map!(a => cast(IdentifierNode)a)
                           .map!(a => getIdentifier(a))
                           .array;
        auto types = right.data["type"]
                          .get!(Type*)
                          .tuple
                          .types;
        auto sizes = types.map!(a => a.size)
                          .array;
        str ~= compileExpression(cast(BoolExprNode)right, vars);
        str ~= "    mov    r10, r8\n";
        foreach (i, ident, type; lockstep(identifiers, types))
        {
            auto alignedIndex = sizes.getAlignedIndexOffset(i);
            auto size = sizes[i];
            str ~= "    mov    r8" ~ getRRegSuffix(size)
                                   ~ ", "
                                   ~ getWordSize(size)
                                   ~ " [r10+"
                                   ~ (MARK_FUNC_PTR
                                    + STRUCT_BUFFER_SIZE
                                    + alignedIndex).to!string
                                   ~ "]"
                                   ~ "\n";
            auto var = new VarTypePair;
            var.varName = ident;
            var.type = type;
            vars.addStackVar(var);
            str ~= vars.compileVarSet(ident);
        }
    }
    return str;
}

string compileSpawnStmt(SpawnStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    vars.runtimeExterns["newProc"] = true;
    auto sig = node.data["sig"].get!(FuncSig*);
    auto argExprs = (cast(TemplateInstantiationNode)node.children[1])
                    ? (cast(ASTNonTerminal)node.children[2]).children
                    : (cast(ASTNonTerminal)node.children[1]).children;
    auto funcArgs = sig.funcArgs;
    auto str = "";

    // TODO update this to handle large types, namely funcptrs

    if (funcArgs.length > 0)
    {
        vars.allocateStackSpace(8);
        auto r12Loc = vars.getTop;
        vars.allocateStackSpace(8);
        auto r13Loc = vars.getTop;
        // Allocate newProc argLens
        str ~= "    mov    rdi, " ~ funcArgs.length.to!string ~ "\n";
        str ~= "    call   malloc\n";
        str ~= "    mov    r12, rax\n";
        foreach (i, arg; funcArgs)
        {
            auto size = arg.type.size;
            // argLens contains a negative size if the value is a floating
            // point argument
            if (arg.type.isFloat)
            {
                size *= -1;
            }
            str ~= "    mov    byte [r12+" ~ i.to!string
                                           ~ "], "
                                           ~ size.to!string
                                           ~ "\n";
        }
        // Store argLens on stack
        str ~= "    mov    qword [rbp-" ~ r12Loc.to!string
                                        ~ "], r12\n";
        // Allocate newProc args
        str ~= "    mov    rdi, " ~ (funcArgs.length * 8).to!string
                                  ~ "\n";
        str ~= "    call   malloc\n";
        str ~= "    mov    r13, rax\n";
        // Store args on stack
        str ~= "    mov    qword [rbp-" ~ r13Loc.to!string
                                        ~ "], r13\n";
        // Populate args with actual arguments
        foreach (i, argExpr; argExprs)
        {
            if (argExpr.data["type"].get!(Type*).size > 8)
            {
                assert(false, "Unimplemented");
            }
            str ~= compileBoolExpr(cast(BoolExprNode)argExpr, vars);
            str ~= "    mov    r13, qword [rbp-" ~ r13Loc.to!string
                                                 ~ "]\n";
            str ~= "    mov    qword [r13+" ~ (i * 8).to!string
                                            ~ "], r8\n";
        }
        // Populate newProc args
        str ~= "    mov    rdi, " ~ funcArgs.length.to!string ~ "\n";
        str ~= "    mov    rsi, " ~ sig.funcName ~ "\n";
        // Retrieve argLens from stack
        str ~= "    mov    rdx, qword [rbp-" ~ r12Loc.to!string
                                             ~ "]\n";
        // Retrieve args from stack
        str ~= "    mov    rcx, qword [rbp-" ~ r13Loc.to!string
                                             ~ "]\n";
        str ~= "    call   newProc\n";
        // Free args and argLens
        str ~= "    mov    rdi, qword [rbp-" ~ r12Loc.to!string
                                             ~ "]\n";
        str ~= "    call   free\n";
        str ~= "    mov    rdi, [rbp-" ~ r13Loc.to!string
                                       ~ "]\n";
        str ~= "    call   free\n";
        vars.deallocateStackSpace(16);
    }
    else
    {
        str ~= "    mov    rdi, 0\n";
        str ~= "    mov    rsi, " ~ sig.funcName ~ "\n";
        str ~= "    mov    rdx, 0\n";
        str ~= "    mov    rcx, 0\n";
        str ~= "    call   newProc\n";
    }
    return str;
}

string compileYieldStmt(YieldStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    vars.runtimeExterns["yield"] = true;
    auto str = "";
    str ~= "    call   yield\n";
    return str;
}

string compileBreakStmt(BreakStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    str ~= "    jmp    " ~ vars.breakLabels[$-1]
                         ~ "\n";
    return str;
}

string compileContinueStmt(ContinueStmtNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    str ~= "    jmp    " ~ vars.continueLabels[$-1]
                         ~ "\n";
    return str;
}

string compileChanWrite(ChanWriteNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    vars.runtimeExterns["yield"] = true;
    vars.runtimeExterns["__mellow_lock_chan_access_mutex"] = true;
    vars.runtimeExterns["__mellow_unlock_chan_access_mutex"] = true;
    auto str = "";
    auto valSize = node.children[1].data["type"].get!(Type*).size;
    str ~= compileBoolExpr(cast(BoolExprNode)node.children[0], vars);
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto chanLoc = vars.getTop;
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto valLoc = vars.getTop;
    str ~= "    mov    qword [rbp-" ~ chanLoc.to!string
                                    ~ "], r8\n";
    str ~= compileBoolExpr(cast(BoolExprNode)node.children[1], vars);
    // Chan is in r9, value is in r8
    str ~= "    mov    r9, qword [rbp-" ~ chanLoc.to!string
                                        ~ "]\n";
    str ~= "    mov    qword [rbp-" ~ valLoc.to!string ~ "], r8\n";
    auto tryWrite = vars.getUniqLabel;
    auto cannotWrite = vars.getUniqLabel;
    auto successfulWrite = vars.getUniqLabel;
    str ~= tryWrite ~ ":\n";
    str ~= "    ; Test if the channel has a valid value in it already,\n";
    str ~= "    ; yield if yes, write if not.\n";
    str ~= "    ;\n";
    str ~= "    ; First, lock the channel access mutex\n";
    str ~= "    mov    r11, qword [r9+" ~ MARK_FUNC_PTR.to!string ~ "]\n";
    str ~= "    ; Get the mutex index\n";
    str ~= "    shr    r11, 16\n";
    str ~= "    and    r11, 0xFFFF\n";
    str ~= "    ; Lock the access mutex for this channel\n";
    str ~= "    mov    rdi, r11\n";
    str ~= "    call   __mellow_lock_chan_access_mutex\n";
    str ~= "    ; Restore channel (r9) and value to write (r8)\n";
    str ~= "    mov    r9, qword [rbp-" ~ chanLoc.to!string ~ "]\n";
    str ~= "    mov    r8, qword [rbp-" ~ valLoc.to!string ~ "]\n";
    str ~= "    ; Get 'contains' bit from chan object header\n";
    str ~= "    mov    r11, qword [r9+" ~ MARK_FUNC_PTR.to!string ~ "]\n";
    str ~= "    and    r11, 1\n";
    str ~= "    cmp    r11, 0\n";
    str ~= "    jne    " ~ cannotWrite ~ "\n";
    str ~= "    mov    " ~ getWordSize(valSize)
                         ~ " [r9+" ~ (MARK_FUNC_PTR + STR_SIZE).to!string
                                   ~ "], r8"
                         ~ getRRegSuffix(valSize)
                         ~ "\n";
    // Set the channel to declare it contains valid data
    str ~= "    or     qword [r9+" ~ MARK_FUNC_PTR.to!string ~ "], 1\n";
    str ~= "    jmp    " ~ successfulWrite
                         ~ "\n";
    str ~= cannotWrite ~ ":\n";
    // Unlock mutex, then yield
    str ~= "    mov    r11, qword [r9+" ~ MARK_FUNC_PTR.to!string ~ "]\n";
    str ~= "    ; Get the mutex index\n";
    str ~= "    shr    r11, 16\n";
    str ~= "    and    r11, 0xFFFF\n";
    str ~= "    ; Unlock the access mutex for this channel\n";
    str ~= "    mov    rdi, r11\n";
    str ~= "    call   __mellow_unlock_chan_access_mutex\n";
    str ~= "    call   yield\n";
    // Restore channel and value, reattempt write
    str ~= "    mov    r9, qword [rbp-" ~ chanLoc.to!string ~ "]\n";
    str ~= "    mov    r8, qword [rbp-" ~ valLoc.to!string ~ "]\n";
    str ~= "    jmp    " ~ tryWrite ~ "\n";
    str ~= successfulWrite ~ ":\n";
    str ~= "    ; Successfully wrote to the channel! Unlocking mutex...\n";
    str ~= "    mov    r11, qword [r9+" ~ MARK_FUNC_PTR.to!string ~ "]\n";
    str ~= "    ; Get the mutex index\n";
    str ~= "    shr    r11, 16\n";
    str ~= "    and    r11, 0xFFFF\n";
    str ~= "    ; Unlock the access mutex for this channel\n";
    str ~= "    mov    rdi, r11\n";
    str ~= "    call   __mellow_unlock_chan_access_mutex\n";
    return str;
}

string compileFuncCall(FuncCallNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    auto funcName = getIdentifier(cast(IdentifierNode)node.children[0]);
    auto isExtern = false;
    // We're dealing with a function pointer, not a straight function call
    if ("funcptrsig" in node.data)
    {
        str ~= vars.compileVarGet(funcName);
        // Get the function ptr itself
        // TODO: Implement passing environment pointer to compileArgList
        str ~= "    mov    r10, qword [r8+24]\n";
    }
    // This is a simple function call
    else
    {
        auto funcSig = node.data["funcsig"].get!(FuncSig*);
        isExtern = funcSig.isExtern;
        str ~= "    mov    r10, " ~ funcName ~ "\n";
    }
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto funcLoc = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ funcLoc ~ "], r10\n";
    ulong numArgs = 0;
    if (cast(TemplateInstantiationNode)node.children[1])
    {
        str ~= compileArgList(
            cast(FuncCallArgListNode)node.children[2], vars
        );
        numArgs = (cast(ASTNonTerminal)node.children[2]).children.length;
    }
    else
    {
        str ~= compileArgList(
            cast(FuncCallArgListNode)node.children[1], vars
        );
        numArgs = (cast(ASTNonTerminal)node.children[1]).children.length;
    }
    str ~= "    mov    r10, qword [rbp-" ~ funcLoc ~ "]\n";
    // TODO: We need to update this to include passing any stack arguments
    //
    // If the function was declared extern, we have to assume it is a C function
    // which will not yield, or do any other stack switching, but may have an
    // arbitrarily deep call stack without doing any of the stack maintenance
    // that normal mellow functions do. So switch out the underlying stack for
    // the main OS stack, which grows for us
    if (isExtern)
    {
        vars.runtimeExterns["__mellow_use_main_stack"] = true;
        // Call the wrapper function with the function to wrap as the only
        // argument.
        //
        // NOTE: We are "passing" in the wrapped function in r10
        str ~= "    call   __mellow_use_main_stack\n";
    }
    // Otherwise, it is a normal mellow function, so call directly
    else
    {
        str ~= "    call   r10\n";
    }
    if (numArgs > 6)
    {

        // TODO replace this with something that doesn't directly affect the
        // stack

        str ~= "    add    rsp, " ~ ((numArgs - 6) * 8).to!string ~ "\n";
    }
    str ~= "    mov    r8, rax\n";
    return str;
}

string compileArgList(FuncCallArgListNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto caseStr = node.data["case"].get!(string);
    final switch (caseStr)
    {
    case "funccall": return compileFuncCallArgList(node, vars);
    case "variant" : return compileVariantArgList(node, vars);
    }
}

string compileFuncCallArgList(FuncCallArgListNode node, Context* vars)
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

string compileVariantArgList(FuncCallArgListNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    // The pointer to the allocated space for the new variant is in r8, set
    // to the correct tag
    auto variantType = node.data["parenttype"].get!(Type*).variantDef;
    auto constructor = node.data["constructor"].get!(string);
    auto member = variantType.getMember(constructor);
    auto memberTypes = member.constructorElems.tuple.types;
    auto memberTypeSizes = memberTypes.map!(a => a.size)
                                      .array;
    auto str = "";
    vars.allocateStackSpace(8);
    auto variantLoc = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ variantLoc
                                    ~ "], r8\n";
    scope (exit) vars.deallocateStackSpace(8);
    foreach (i, child; node.children)
    {
        auto type = child.data["type"].get!(Type*);
        str ~= compileExpression(child, vars);
        switch (type.size)
        {
        case 16:
            assert(false, "Unimplemented");
            break;
        case 1:
        case 2:
        case 4:
        case 8:
        default:
            auto memberOffset = memberTypeSizes.getAlignedIndexOffset(i);
            str ~= "    mov    r10, qword [rbp-" ~ variantLoc
                                                 ~ "]\n";
            str ~= "    add    r10, " ~ (MARK_FUNC_PTR
                                       + VARIANT_TAG_SIZE
                                       + memberOffset).to!string
                                      ~ "\n";
            str ~= "    mov    " ~ getWordSize(type.size)
                                 ~ " [r10], "
                                 ~ "r8"
                                 ~ getRRegSuffix(type.size)
                                 ~ "\n";
            break;
        }
    }
    str ~= "    mov    r8, qword [rbp-" ~ variantLoc
                                        ~ "]\n";
    return str;
}
