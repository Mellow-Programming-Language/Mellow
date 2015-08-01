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
import std.regex;
import std.path;
import parser;
import visitor;
import Record;
import typedecl;
import Function;
import FunctionSig;
import CodeGenerator;
import Namespace;

int main(string[] argv)
{
    auto context = new TopLevelContext;
    version (MULTITHREAD)
    {
        context.runtimePath = "runtime/runtime_multithread.o";
    }
    else
    {
        context.runtimePath = "runtime/runtime.o";
    }
    context.outfileName = "a.out";
    context.stdlibPath = "stdlib";
    context.compileOnly = false;
    context.dump = false;
    context.help = false;
    context.keepObjs = false;
    context.assembleOnly = false;
    try
    {
        getopt(argv,
            "outfile|o", &context.outfileName,
            "keep|k", &context.keepObjs,
            "c", &context.assembleOnly,
            "runtime", &context.runtimePath,
            "stdlib", &context.stdlibPath,
            "S", &context.compileOnly,
            "dump", &context.dump,
            "help", &context.help);
    }
    catch (Exception ex)
    {
        writeln("Error: Unrecognized cmdline argument.");
        return 1;
    }
    if (context.assembleOnly)
    {
        context.keepObjs = true;
    }
    if (context.help)
    {
q"EOF
All arguments must be prefaced by double dashes, as in --help or --o.

--dump          Inelegantly dump varied information about the parsing and
                analyzing process.

--help          Print this help text and exit.

--outfile S
--o S           Provide a string S which will act as the filename of the
                generated outfile.

--keep
--k             Don't delete the generated object files.

--c             Compile and assemble only, don't link. (Implies --keep)

--runtime S     Provide the path to the runtime object file, if the default is
                incorrect.

--S             Compile only, don't assemble or link.

--stdlib S      Provide the path to the stdlib directory.
EOF".write;
        return 0;
    }
    // Strip program name from arguments
    argv = argv[1..$];
    string[] stdObjs;
    try
    {
        stdObjs = extractNamespacesIntoContext(argv, context);
    }
    catch (Exception e)
    {
        return 1;
    }
    foreach (infileName; context.namespaces.byKey)
    {
        context.namespaces[infileName] = extractFuncSigs(infileName, context);
    }
    string[] objFileNames;
    foreach (infileName; context.namespaces.byKey)
    {
        if (!context.namespaces[infileName].isStd)
        {
            auto objFileName = compileFile(infileName, context);
            if (objFileName == "")
            {
                return 1;
            }
            objFileNames ~= objFileName;
        }
    }

    if (!context.assembleOnly)
    {
        try
        {
            string[] cmd = ["gcc"];
            version (MULTITHREAD)
            {
                cmd = ["-pthread"];
            }
            cmd ~= ["-o"]
                ~ [context.outfileName]
                ~ objFileNames
                ~ stdObjs
                ~ [context.runtimePath]
                ~ ["stdlib.o".absolutePath(context.stdlibPath.absolutePath)];
            auto gccPid = spawnProcess(cmd);
            auto retCode = wait(gccPid);
            if (retCode != 0)
            {
                writeln("Error: [" ~ cmd.join(" ") ~ "] failed");
                return retCode;
            }
        }
        catch (ProcessException ex)
        {
            writeln(
                "Error: Could not exec [gcc]. Do you have it installed?"
            );
            return 1;
        }
    }
    if (!context.keepObjs)
    {
        foreach (obj; objFileNames)
        {
            remove(obj);
        }
    }

    return 0;
}

string[] extractNamespacesIntoContext(string[] filenames,
                                      TopLevelContext* context)
{
    bool[string] names;
    foreach (a; filenames)
    {
        auto abs = a.absolutePath
                    .stripTrailingSlash;
        names[abs] = true;
    }
    string[] stdObjs;
    foreach (infileName; names.byKey())
    {
        if (infileName !in context.namespaces)
        {
            ModuleNamespace* newNamespace;
            newNamespace = extractNamespace(infileName, context);
            context.namespaces[infileName] = newNamespace;
            if (context.dump)
            {
                foreach (structDef; newNamespace.records.structDefs.values)
                {
                    structDef.formatFull.writeln;
                }
                foreach (variantDef; newNamespace.records.variantDefs.values)
                {
                    variantDef.formatFull.writeln;
                }
            }
            bool[string] decendImports;
            ImportPath*[] newImports = newNamespace.imports;
            ImportPath*[] buildImports;
            foreach (imp; newImports)
            {
                decendImports[imp.path] = true;
            }
            while (newImports.length > 0)
            {
                foreach (absPath; newImports)
                {
                    if (absPath.path !in names
                        && absPath.path !in context.namespaces)
                    {
                        if (absPath.isStd)
                        {
                            stdObjs ~= [absPath.path ~ ".o"];
                        }
                        try
                        {
                            newNamespace = extractNamespace(
                                absPath.path ~ ".mlo", context
                            );
                        }
                        catch (Exception e)
                        {
                            writeln(
                                "Error: Could not find file [" ~ absPath.path
                                                               ~ ".mlo"
                                                               ~ "]"
                            );
                            throw e;
                        }
                        newNamespace.isStd = absPath.isStd;
                        buildImports ~= newNamespace.imports;
                        context.namespaces[absPath.path] = newNamespace;
                        if (context.dump)
                        {
                            foreach (structDef; newNamespace.records.structDefs.values)
                            {
                                structDef.formatFull.writeln;
                            }
                            foreach (variantDef; newNamespace.records.variantDefs.values)
                            {
                                variantDef.formatFull.writeln;
                            }
                        }
                    }
                }
                newImports = [];
                foreach (imp; buildImports)
                {
                    if (imp.path !in decendImports)
                    {
                        newImports ~= imp;
                        decendImports[imp.path] = true;
                    }
                }
                buildImports = [];
            }
        }
    }
    return stdObjs;
}

ModuleNamespace* extractNamespace(string infileName, TopLevelContext* context)
{
    auto source = "";
    try
    {
        source = readText(infileName);
    }
    catch (Exception ex)
    {
        writeln("Error: Could not read file [" ~ infileName ~ "].");
        throw new Exception("");
    }
    source = stripComments(source);
    auto parser = new Parser(source);
    auto topNode = parser.parse();
    if (topNode is null)
    {
        writeln("Error: Could not parse program in file [" ~ infileName ~ "].");
        throw new Exception("");
    }
    auto records = new RecordBuilder(cast(ProgramNode)topNode);
    auto imports = (cast(ProgramNode)topNode)
                  .children
                  .filter!(a => typeid(a) == typeid(ImportStmtNode))
                  .map!(a => cast(ImportStmtNode)a)
                  .map!(a => cast(ImportLitNode)(a.children[0]))
                  .map!(a => (cast(ASTTerminal)(a.children[0])).token.to!string)
                  .map!(a => a.translateImportToPath(context))
                  .array;
    return new ModuleNamespace(
        infileName, cast(ProgramNode)topNode, records, imports
    );
}

ModuleNamespace* extractFuncSigs(string infileName, TopLevelContext* context)
{
    auto namespace = context.namespaces[infileName];
    foreach (imp; namespace.imports)
    {
        foreach (sd; context.namespaces[imp.path].records.structDefs.byKey())
        {
            if (sd !in namespace.records.structDefs)
            {
                namespace.records.structDefs[sd] = context.namespaces[imp.path]
                                                          .records
                                                          .structDefs[sd];
            }
        }
        foreach (vd; context.namespaces[imp.path].records.variantDefs.byKey())
        {
            if (vd !in namespace.records.variantDefs)
            {
                namespace.records.variantDefs[vd] = context.namespaces[imp.path]
                                                           .records
                                                           .variantDefs[vd];
            }
        }
    }
    // Just do function definitions
    auto funcDefs = namespace
        .topNode
        .children
        .filter!(a => typeid(a) == typeid(FuncDefNode)
                   || typeid(a) == typeid(ExternFuncDeclNode));
    FuncSig*[] funcSigs;
    foreach (funcDef; funcDefs)
    {
        auto builder = new FunctionSigBuilder(funcDef, namespace.records);
        funcSigs ~= builder.funcSig;
    }
    namespace.funcSigs = funcSigs;
    return namespace;
}

string compileFile(string infileName, TopLevelContext* context)
{
    auto namespace = context.namespaces[infileName];
    foreach (imp; namespace.imports)
    {
        foreach (sd; context.namespaces[imp.path].records.structDefs.byKey())
        {
            if (sd !in namespace.records.structDefs)
            {
                namespace.records.structDefs[sd] = context.namespaces[imp.path]
                                                          .records
                                                          .structDefs[sd];
            }
        }
        foreach (vd; context.namespaces[imp.path].records.variantDefs.byKey())
        {
            if (vd !in namespace.records.variantDefs)
            {
                namespace.records.variantDefs[vd] = context.namespaces[imp.path]
                                                           .records
                                                           .variantDefs[vd];
            }
        }
        namespace.externFuncSigs ~= context.namespaces[imp.path]
                                           .funcSigs;
    }
    auto funcs = new FunctionBuilder(
        namespace.topNode,
        namespace.records,
        namespace.funcSigs,
        namespace.externFuncSigs
    );
    auto fullAsm = compileProgram(namespace.records, funcs);
    if (context.compileOnly)
    {
        try
        {
            std.file.write(context.outfileName, fullAsm);
        }
        catch (Exception ex)
        {
            writeln(
                "Error: Could not write outfile [" ~ context.outfileName ~ "]."
            );
            return "";
        }
    }
    else
    {
        auto asmTmpfileName = generateRandomFilename() ~ ".asm";
        auto objectTmpfileName = infileName.stripExtension ~ ".o";
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
            return "";
        }
        scope (exit) remove(asmTmpfileName);
        try
        {
            auto nasmPid = spawnProcess(
                ["nasm", "-f", "elf64", "-o", objectTmpfileName, asmTmpfileName]
            );
            auto retCode = wait(nasmPid);
            if (retCode != 0)
            {
                writeln(
                    "Error: [nasm -f elf64 -o " ~ objectTmpfileName ~ " "
                    ~ asmTmpfileName ~ "] failed"
                );
                return "";
            }
        }
        catch (ProcessException ex)
        {
            writeln("Error: Could not exec [nasm]. Do you have it installed?");
            return "";
        }
        if (exists(objectTmpfileName))
        {
            return objectTmpfileName;
        }
    }
    return "";
}

string stripComments(string source)
{
    // FIXME: This does not handle double slash in quotes
    return replaceAll(source, regex(r"//.*$", "gm"), "\n");
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
    header ~= "    SECTION .text\n";
    if ("main" in context.externFuncs || "main" in context.compileFuncs)
    {
        header ~= "    global main\n";
    }
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
