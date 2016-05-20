import std.regex;
import std.array;
import std.path;
import Record;
import Function;
import typedecl;
import parser;

struct TopLevelContext
{
    ModuleNamespace*[string] namespaces;
    Type*[string] allEncounteredTypes;
    string outfileName;
    string stdlibPath;
    string runtimePath;
    bool compileOnly;
    bool dump;
    bool debugSymbols;
    bool help;
    bool keepObjs;
    bool assembleOnly;
    bool unittests;
    bool generateMain;
    bool mainTakesArgv;
    bool stacktrace;
    bool release;
    bool verbose;
}

struct ModuleNamespace
{
    string moduleName;
    ProgramNode topNode;
    RecordBuilder records;
    FuncSig*[] funcSigs;
    FuncSig*[] externFuncSigs;
    ImportPath*[] imports;
    bool isStd;

    this (string moduleName, ProgramNode topNode,
          RecordBuilder records, ImportPath*[] imports)
    {
        this.moduleName = moduleName;
        this.topNode = topNode;
        this.records = records;
        this.imports = imports;
        this.isStd = false;
    }
}

string stripTrailingSlash(string input)
{
    if (input[$-1] == '/')
    {
        return input[0..$-1];
    }
    return input;
}

struct ImportPath
{
    string path;
    bool isStd;
}

ImportPath* translateImportToPath(string imp, TopLevelContext* context)
{
    auto pathParts = imp.split(".");
    auto importPath = new ImportPath();
    if (pathParts[0] == "std")
    {
        if (pathParts.length < 2)
        {
            throw new Exception("Error: `import std;` is invalid");
        }
        importPath.path = pathParts.array[1..$]
                                   .join("/")
                                   .absolutePath(context.stdlibPath.absolutePath)
                                   .stripTrailingSlash;
        importPath.isStd = true;
    }
    else
    {
        importPath.path = pathParts.array
                                   .join("/")
                                   .absolutePath
                                   .stripTrailingSlash;
        importPath.isStd = false;
    }
    return importPath;
}
