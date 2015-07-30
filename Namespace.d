
import Record;
import Function;
import typedecl;
import parser;

struct ModuleNamespace
{
    string moduleName;
    ProgramNode topNode;
    RecordBuilder records;
    FuncSig*[] funcSigs;

    this (string moduleName, ProgramNode topNode,
          RecordBuilder records, FuncSig*[] funcSigs)
    {
        this.moduleName = moduleName;
        this.topNode = topNode;
        this.records = records;
        this.funcSigs = funcSigs;
    }
}
