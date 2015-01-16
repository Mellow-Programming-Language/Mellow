import std.stdio;
import std.algorithm;
import std.conv;
import std.range;
import std.array;
import parser;
import visitor;
import Record;
import typedecl;
import Function;
import FunctionSig;
import CodeGenerator;

int main(string[] argv)
{
    string line = "";
    string source = "";
    while ((line = stdin.readln) !is null)
    {
        source ~= line;
    }
    auto parser = new Parser(source);
    auto topNode = parser.parse();
    if (topNode !is null)
    {
        auto records = new RecordBuilder(cast(ProgramNode)topNode);
        auto funcSigs = new FunctionSigBuilder(cast(ProgramNode)topNode,
            records);
        auto funcs = new FunctionBuilder(cast(ProgramNode)topNode, records,
            funcSigs);
        auto isThreads = false;
        foreach (structDef; records.structDefs.values)
        {
            writeln(structDef.formatFull());
        }
        foreach (variantDef; records.variantDefs.values)
        {
            writeln(variantDef.format());
        }
        foreach (sig; funcSigs.toplevelFuncs)
        {
            sig.format.writeln;
        }
        auto context = new Context();
        context.structDefs = records.structDefs;
        context.variantDefs = records.variantDefs;
        foreach (sig; funcs.getExternFuncSigs)
        {
            context.externFuncs[sig.funcName] = sig;
        }
        auto mainExists = false;
        auto mainTakesArgv = false;
        foreach (sig; funcs.getCompilableFuncSigs)
        {
            context.compileFuncs[sig.funcName] = sig;
            if (sig.funcName == "main")
            {
                mainExists = true;
                sig.funcName = "__ZZmain";
                if (sig.funcArgs.length > 1)
                {
                    throw new Exception("main() can only take 0 or 1 args");
                }
                else if (sig.funcArgs.length == 1)
                {
                    if (sig.funcArgs[0].type.tag != TypeEnum.ARRAY
                        || sig.funcArgs[0].type.array.arrayType.tag
                           != TypeEnum.STRING)
                    {
                        throw new Exception("main() can only receive []string");
                    }
                    else
                    {
                        mainTakesArgv = true;
                    }
                }
                if (sig.returnType.tag != TypeEnum.VOID)
                {
                    throw new Exception("main() cannot return a value");
                }
            }
        }
        auto str = "";
        auto header = "";
        if (funcs.getCompilableFuncSigs.length > 0)
        {
            str ~= funcs.getCompilableFuncSigs
                        .map!(a => a.compileFunction(context))
                        .reduce!((a, b) => a ~ "\n" ~ b);
            if (mainExists)
            {
                str ~= compileEntryPoint(mainTakesArgv, isThreads);
            }
        }
        header ~= "    extern malloc\n"
                ~ "    extern free\n"
                ~ "    extern strlen\n"
                ~ "    extern memcpy\n";
        if (funcs.getExternFuncSigs.length > 0)
        {
            header ~= funcs.getExternFuncSigs
                           .map!(a => "    extern " ~ a.funcName ~ "\n")
                           .reduce!((a, b) => a ~ b);
        }
        header ~= "    SECTION .data\n";
        if (context.dataEntries.length > 0)
        {
            header ~= context.dataEntries
                             .map!(a => a.label ~ ": db " ~ a.data ~ "\n")
                             .reduce!((a, b) => a ~ b);
        }
        if (context.floatEntries.length > 0)
        {
            header ~= context.floatEntries
                             .map!(a => a.label ~ ": dq " ~ a.floatStr ~ "\n")
                             .reduce!((a, b) => a ~ b);
        }
        header ~= "    SECTION .text\n"
                ~ "    global main\n";
        auto full = header ~ str;
        full.writeln;
    }
    else
    {
        writeln("Failed to parse!");
    }
    return 0;
}

string compileEntryPoint(bool mainTakesArgv, bool threads)
{
    auto str = "";
    str ~= "main:\n";
    str ~= "    push   rbp\n";
    str ~= "    mov    rbp, rsp\n";
    if (threads)
    {
        if (mainTakesArgv)
        {
            str ~= "    sub    rsp, 32\n";
            str ~= "    mov    qword [rbp-8], rdi\n";
            str ~= "    mov    qword [rbp-16], rsi\n";
            str ~= "    call   initThreadManager\n";
            // Allocate newProc argLens
            str ~= "    mov    rdi, 1\n";
            str ~= "    call   malloc\n";
            str ~= "    mov    r12, rax\n";
            str ~= "    mov    byte [r12], 8\n";
            // Store argLens on stack
            str ~= "    mov    qword [rbp-24], r12\n";
            // Allocate newProc args
            str ~= "    mov    rdi, 8\n";
            str ~= "    call   malloc\n";
            str ~= "    mov    r13, rax\n";
            // Store args on stack
            str ~= "    mov    qword [rbp-32], r13\n";
            // Retrieve argc in rdi
            str ~= "    mov    rdi, qword [rbp-8]\n";
            // Retrieve argv in rsi
            str ~= "    mov    rsi, qword [rbp-16]\n";
            str ~= compileArgvStringArray();
            // Retrieve args and set []string argv in args
            str ~= "    mov    r10, qword [rbp-32]\n";
            str ~= "    mov    qword [r10], r8\n";
            str ~= "    mov    rdi, 1\n";
            str ~= "    mov    rsi, __ZZmain\n";
            // Retrieve argLens from stack
            str ~= "    mov    rdx, qword [rbp-24]\n";
            str ~= "    mov    rcx, r10\n";
            str ~= "    call   newProc\n";
            // Free args and argLens
            str ~= "    mov    rdi, [rbp-24]\n";
            str ~= "    call   free\n";
            str ~= "    mov    rdi, [rbp-32]\n";
            str ~= "    call   free\n";
        }
        else
        {
            str ~= "    call   initThreadManager\n";
            str ~= "    mov    rdi, 0\n";
            str ~= "    mov    rsi, __ZZmain\n";
            str ~= "    mov    rdx, 0\n";
            str ~= "    mov    rcx, 0\n";
            str ~= "    call   newProc\n";
        }
        str ~= "    call   execScheduler\n";
        str ~= "    call   takedownThreadManager\n";
    }
    else
    {
        if (mainTakesArgv)
        {
            str ~= compileArgvStringArray();
            str ~= "    mov    rdi, r8\n";
        }
        str ~= "    call   __ZZmain\n";
    }
    str ~= "    mov    rax, 0\n";
    str ~= "    leave\n";
    str ~= "    ret\n";
    return str;
}

// This assembly algorithm assumes the OS-provided argc is in rdi, the
// OS-provided argv is in rsi, and provides the []string argv-equivalent in
// r8
string compileArgvStringArray()
{
    auto str = q"EOF
    ; argc is in rdi, and in r14
    mov    r14, rdi
    ; argv is in rsi, and in r15
    mov    r15, rsi
    ; Get alloc size for []string in rdi using getAllocSize algorithm
    mov    r8, rdi
    sub    r8, 1
    mov    rdi, r8
    shr    rdi, 1
    or     rdi, r8
    mov    r8, rdi
    shr    r8, 2
    or     rdi, r8
    mov    r8, rdi
    shr    r8, 4
    or     rdi, r8
    mov    r8, rdi
    shr    r8, 8
    or     rdi, r8
    mov    r8, rdi
    shr    r8, 16
    or     rdi, r8
    mov    r8, rdi
    shr    r8, 32
    or     rdi, r8
    add    rdi, 1
    ; Add space for ref count and array length
    add    rdi, 8
    call   malloc
    ; Store []string in r13
    mov    r13, rax
    ; Set refcount to 1
    mov    dword [r13], 1
    ; Set []string length
    mov    dword [r13+4], r14d
    ; r12 is the counter for looping through argc
    mov    r12, 0
.loop:
    cmp    r12, r14
    je     .endloop
    ; Get offset into argv for next string
    mov    r9, r15
    mov    r10, r12
    imul   r10, 8
    add    r9, r10
    mov    rdi, qword [r9]
    call   strlen
    ; string length in rax, get alloc size for string in r9, save rax in rbx
    mov    r8, rax
    mov    rbx, rax
    sub    r8, 1
    mov    r9, r8
    shr    r9, 1
    or     r9, r8
    mov    r8, r9
    shr    r8, 2
    or     r9, r8
    mov    r8, r9
    shr    r8, 4
    or     r9, r8
    mov    r8, r9
    shr    r8, 8
    or     r9, r8
    mov    r8, r9
    shr    r8, 16
    or     r9, r8
    mov    r8, r9
    shr    r8, 32
    or     r9, r8
    add    r9, 1
    ; Allocate space for string. Alloc space plus ref count plus string size
    ; plus space for the null byte
    mov    rdi, r9
    add    rdi, 9
    call   malloc
    ; Set ref count to 1 for new string
    mov    dword [rax], 1
    ; Set string length for new string
    mov    dword [rax+4], ebx
    ; Place pointer for string into []string, which is still in r13.
    ; Need to calculate offset into r13 using the r12 counter
    mov    r8, r13
    add    r8, 8
    mov    r9, r12
    imul   r9, 8
    add    r8, r9
    mov    qword [r8], rax
    ; Get offset into new string in rdi for memcpy
    mov    rdi, rax
    add    rdi, 8
    ; Get offset into argv again for the same string, for memcpy
    mov    r9, r15
    mov    r10, r12
    imul   r10, 8
    add    r9, r10
    mov    rsi, qword [r9]
    ; Set number of bytes to copy, including the null byte
    mov    rdx, rbx
    add    rdx, 1
    call   memcpy
    ; Increment counter and loop
    add    r12, 1
    jmp    .loop
.endloop:
    ; r8 now contains []string argv
    mov    r8, r13
EOF";
    return str;
}
