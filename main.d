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
        foreach (sig; funcs.getCompilableFuncSigs)
        {
            context.compileFuncs[sig.funcName] = sig;
        }
        auto str = "";
        auto header = "";
        if (funcs.getCompilableFuncSigs.length > 0)
        {
            str ~= funcs.getCompilableFuncSigs
                        .map!(a => a.compileFunction(context))
                        .reduce!((a, b) => a ~ "\n" ~ b);
        }
        header ~= "    extern malloc\n"
                ~ "    extern free\n"
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
