import std.stdio;
import std.algorithm;
import std.conv;
import std.range;
import std.array;
import std.getopt;
import std.process;
import std.file;
import std.ascii;
import std.random;
import parser;
import visitor;
import Record;
import typedecl;
import Function;
import FunctionSig;
import CodeGenerator;

int main(string[] argv)
{
    string outfileName = "a.out";
    version (MULTITHREAD)
    {
        string runtimePath = "runtime/runtime_multithread.o";
    }
    else
    {
        string runtimePath = "runtime/runtime.o";
    }
    string stdlibPath = "stdlib/stdlib.o";
    bool compileOnly = false;
    bool dump = false;
    bool help = false;
    try
    {
        getopt(argv,
            "outfile|o", &outfileName,
            "runtime", &runtimePath,
            "stdlib", &stdlibPath,
            "S", &compileOnly,
            "dump", &dump,
            "help", &help);
    }
    catch (Exception ex)
    {
        writeln("Error: Unrecognized cmdline argument.");
        return 0;
    }
    if (help)
    {
q"EOF
All arguments must be prefaced by double dashes, as in --help or --o.

--dump          Inelegantly dump varied information about the parsing and
                analyzing process.

--help          Print this help text and exit.

--outfile S
--o S           Provide a string S which will act as the filename of the
                generated outfile.

--runtime S     Provide the path to the runtime object file, if the default is
                incorrect.

--S             Only generate the assembly file, don't assemble or link.

--stdlib S      Provide the path to the stdlib object file, if the default is
                incorrect.
EOF".write;
        return 0;
    }
    // Strip program name from arguments
    argv = argv[1..$];
    if (argv.length != 1)
    {
        writeln(argv);
        writeln("Error: Exactly one filename must be passed for compilation.");
        return 0;
    }
    auto infileName = argv[0];
    auto source = "";
    try
    {
        source = readText(infileName);
    }
    catch (Exception ex)
    {
        writeln("Error: Could not read file [" ~ infileName ~ "].");
        return 0;
    }
    auto parser = new Parser(source);
    auto topNode = parser.parse();
    if (topNode is null)
    {
        writeln("Error: Could not parse program in file [" ~ infileName ~ "].");
        return 0;
    }
    auto records = new RecordBuilder(cast(ProgramNode)topNode);
    // Just do function definitions
    auto funcDefs =
        (cast(ProgramNode)
        topNode).children
               .filter!(a => typeid(a) == typeid(FuncDefNode)
                          || typeid(a) == typeid(ExternFuncDeclNode));
    FuncSig*[] funcSigs;
    foreach (funcDef; funcDefs)
    {
        auto builder = new FunctionSigBuilder(funcDef, records);
        funcSigs ~= builder.funcSig;
    }
    auto funcs = new FunctionBuilder(cast(ProgramNode)topNode, records,
        funcSigs);
    if (dump)
    {
        foreach (structDef; records.structDefs.values)
        {
            writeln(structDef.formatFull());
        }
        foreach (variantDef; records.variantDefs.values)
        {
            writeln(variantDef.format());
        }
        foreach (sig; funcSigs)
        {
            sig.format.writeln;
        }
    }
    auto fullAsm = compileProgram(records, funcs);
    if (compileOnly)
    {
        try
        {
            std.file.write(outfileName, fullAsm);
        }
        catch (Exception ex)
        {
            writeln("Error: Could not write outfile [" ~ outfileName ~ "].");
            return 0;
        }
    }
    else
    {
        auto asmTmpfileName = generateRandomFilename() ~ ".asm";
        auto objectTmpfileName = generateRandomFilename() ~ ".o";
        try
        {
            auto tempAsmFile = File(asmTmpfileName, "wx");
            tempAsmFile.write(fullAsm);
        }
        catch (Exception ex)
        {
            writeln(
                "Error: Could not write to tempfile [" ~ asmTmpfileName ~ "]."
            );
            return 0;
        }
        scope (exit) remove(asmTmpfileName);
        try
        {
            auto nasmPid = spawnProcess(
                ["nasm", "-f", "elf64", "-o", objectTmpfileName, asmTmpfileName]
            );
            wait(nasmPid);
        }
        catch (ProcessException ex)
        {
            writeln("Error: Could not exec [nasm]. Do you have it installed?");
            return 0;
        }
        if (exists(objectTmpfileName))
        {
            scope (exit) remove(objectTmpfileName);
            try
            {
                version (MULTITHREAD)
                {
                    auto gccPid = spawnProcess(
                        [
                            "gcc", "-pthread", "-o", outfileName,
                            objectTmpfileName, stdlibPath, runtimePath
                        ]
                    );
                }
                else
                {
                    auto gccPid = spawnProcess(
                        [
                            "gcc", "-o", outfileName, objectTmpfileName,
                            stdlibPath, runtimePath
                        ]
                    );
                }
                wait(gccPid);
            }
            catch (ProcessException ex)
            {
                writeln(
                    "Error: Could not exec [gcc]. Do you have it installed?"
                );
                return 0;
            }
        }
    }
    return 0;
}

string generateRandomFilename()
{
    auto str = "";
    foreach (i; 0..32)
    {
        str ~= std.ascii.letters[uniform(0, $)];
    }
    return str;
}

string compileProgram(RecordBuilder records, FunctionBuilder funcs)
{
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
                    .map!(a => compileFunction(a, context))
                    .reduce!((a, b) => a ~ "\n" ~ b);
        if (mainExists)
        {
            str ~= "\n";
            str ~= compileEntryPoint(mainTakesArgv, context);
        }
    }
    header ~= "    extern malloc\n"
            ~ "    extern realloc\n"
            ~ "    extern free\n"
            ~ "    extern memcpy\n";
    if (context.runtimeExterns.length > 0)
    {
        header ~= context.runtimeExterns
                         .keys
                         .map!(a => "    extern " ~ a ~ "\n")
                         .reduce!((a, b) => a ~ b);
    }
    if (funcs.getExternFuncSigs.length > 0)
    {
        header ~= funcs.getExternFuncSigs
                       .map!(a => "    extern " ~ a.funcName ~ "\n")
                       .reduce!((a, b) => a ~ b);
    }
    if (context.bssQWordAllocs.length > 0)
    {
        header ~= "    SECTION .bss\n";
        foreach (label; context.bssQWordAllocs.keys)
        {
            header ~= label ~ ": resq 1\n";
        }
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
    return full;
}

string compileEntryPoint(bool mainTakesArgv, Context* vars)
{
    auto str = "";
    str ~= "main:\n";
    str ~= "    push   rbp\n";
    str ~= "    mov    rbp, rsp\n";
    // If we use green threads functionality, enable the green threads runtime
    if ("newProc" in vars.runtimeExterns
        || "yield" in vars.runtimeExterns)
    {
        vars.runtimeExterns["initThreadManager"] = true;
        vars.runtimeExterns["execScheduler"] = true;
        vars.runtimeExterns["takedownThreadManager"] = true;
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
            str ~= compileArgvStringArray(vars);
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
            str ~= compileArgvStringArray(vars);
            str ~= "    mov    rdi, r8\n";
        }
        str ~= "    call   __ZZmain\n";
    }
    str ~= "    mov    rax, 0\n";
    str ~= "    mov    rsp, rbp    ; takedown stack frame\n";
    str ~= "    pop    rbp\n";
    str ~= "    ret\n";
    return str;
}

// This assembly algorithm assumes the OS-provided argc is in rdi, the
// OS-provided argv is in rsi, and provides the []string argv-equivalent in
// r8
string compileArgvStringArray(Context* vars)
{
    vars.runtimeExterns["strlen"] = true;
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
    ; Multiply alloc'd space by the size of string ptrs
    imul   rdi, 8
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
