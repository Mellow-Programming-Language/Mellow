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
    string outfileName;
    string stdlibPath;
    string runtimePath;
    bool compileOnly;
    bool dump;
    bool help;
    bool keepObjs;
}

struct ModuleNamespace
{
    string moduleName;
    ProgramNode topNode;
    RecordBuilder records;
    FuncSig*[] funcSigs;
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
    auto reg = ctRegex!(`^(?:([a-zA-Z_][a-zA-Z0-9_]*)(?:\.([a-zA-Z_][a-zA-Z0-9_]*))*)`);
    auto mat = matchAll(imp, reg);
    auto importPath = new ImportPath();
    if (!mat)
    {
        throw new Exception("Mismatch between `import` regexes!");
    }
    if (mat.captures[1] == "std")
    {
        if (mat.captures.length <= 2)
        {
            throw new Exception("Error: `import std;` is invalid");
        }
        importPath.path = mat.captures
                             .array[2..$]
                             .join("/")
                             .absolutePath(context.stdlibPath.absolutePath)
                             .stripTrailingSlash;
        importPath.isStd = true;
    }
    else
    {
        importPath.path = mat.captures
                             .array[1..$]
                             .join("/")
                             .absolutePath
                             .stripTrailingSlash;
        importPath.isStd = false;
    }
    return importPath;
}
