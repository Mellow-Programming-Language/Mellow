import std.algorithm;
import std.conv;
import std.stdio;
import std.range;
import parser;
import visitor;
import CodeGenerator;
import typedecl;

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

string exprOp(string op, string descendNode)
{
    return `
    str ~= node.children
               .map!(a => compile` ~ descendNode
                                   ~ `(cast(` ~ descendNode ~ `Node`
                                   ~ `)a, vars))
               .reduce!((a, b) => a ~ b);
    auto type = node.data["type"].get!(Type*);
    str ~= "    mov    r8, " ~ type.getWordSize ~ "[rbp-"
        ~ vars.getStackPtrOffset.to!string ~ "\n";
    vars.deallocateTempSpace();
    foreach (i; 0..node.children.length - 1)
    {
        str ~= "    mov    r9, " ~ type.getWordSize ~ "[rbp-"
            ~ vars.getStackPtrOffset.to!string ~ "\n";
        vars.deallocateTempSpace();
        str ~= "    ` ~ op ~ `     r8, r9\n";
    }
    vars.allocateTempSpace(type.size);
    str ~= "    mov    [rbp-" ~ vars.getStackPtrOffset.to!string ~ "], r8\n";
    `;
}

string compileExpression(ASTNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return compileBoolExpr(cast(BoolExprNode)node, vars);
}

string compileBoolExpr(BoolExprNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return compileOrTest(cast(OrTestNode)node.children[0], vars);
}

string compileOrTest(OrTestNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    if (node.children.length == 1)
    {
        return compileAndTest(cast(AndTestNode)node.children[0], vars);
    }
    auto str = "";
    mixin(exprOp("or", "AndTest"));
    return str;
}

string compileAndTest(AndTestNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    if (node.children.length == 1)
    {
        return compileNotTest(cast(NotTestNode)node.children[0], vars);
    }
    auto str = "";
    mixin(exprOp("and", "NotTest"));
    return str;
}

string compileNotTest(NotTestNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    auto child = node.children[0];
    auto type = node.data["type"].get!(Type*);
    if (cast(NotTestNode)child)
    {
        str ~= compileNotTest(cast(NotTestNode)child, vars);
        str ~= "    mov    r8, " ~ type.getWordSize ~ "[rbp-"
            ~ vars.getStackPtrOffset.to!string ~ "\n";
        vars.deallocateTempSpace();
        str ~= "    not    r8\n";
        vars.allocateTempSpace(type.size);
        str ~= "    mov    [rbp-" ~ vars.getStackPtrOffset.to!string
                                  ~ "], r8\n";
    }
    else
    {
        str ~= compileComparison(cast(ComparisonNode)child, vars);
    }
    return str;
}

string compileComparison(ComparisonNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    if (node.children.length == 1)
    {
        return compileExpr(cast(ExprNode)node.children[0], vars);
    }
    return "";
}

string compileExpr(ExprNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return compileOrExpr(cast(OrExprNode)node.children[0], vars);;
}

string compileOrExpr(OrExprNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    if (node.children.length == 1)
    {
        return compileXorExpr(cast(XorExprNode)node.children[0], vars);
    }
    auto str = "";
    mixin(exprOp("or", "XorExpr"));
    return str;
}

string compileXorExpr(XorExprNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    if (node.children.length == 1)
    {
        return compileAndExpr(cast(AndExprNode)node.children[0], vars);
    }
    auto str = "";
    mixin(exprOp("xor", "AndExpr"));
    return str;
}

string compileAndExpr(AndExprNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    if (node.children.length == 1)
    {
        return compileShiftExpr(cast(ShiftExprNode)node.children[0], vars);
    }
    auto str = "";
    mixin(exprOp("and", "ShiftExpr"));
    return str;
}

string compileShiftExpr(ShiftExprNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return compileSumExpr(cast(SumExprNode)node.children[0], vars);
}

string compileSumExpr(SumExprNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    if (node.children.length == 1)
    {
        return compileProductExpr(cast(ProductExprNode)node.children[0], vars);
    }
    auto str = "";
    str ~= compileProductExpr(cast(ProductExprNode)node.children[0], vars);
    Type* leftType = node.children[0].data.get!(Type*);
    Type* rightType;
    for (auto i = 2; i < node.children.length; i += 2)
    {
        str~= "    push   r8\n";
        str ~= compileProductExpr(cast(ProductExprNode)node.children[i], vars);
        auto op = (cast(ASTTerminal)node.children[i-1]).token;
        rightType = node.children[i].data.get!(Type*);
        if (leftType.isIntegral && rightType.isIntegral)
        {
            str ~= "    pop    r9\n";
            final switch (op)
            {
            case "+":
                str ~= "    add    r8, r9\n";
                break;
            case "-":
                str ~= "    sub    r9, r8\n";
                str ~= "    mov    r8, r9\n";
                break;
            }
        }
        else {}
    }
    return str;
}

string compileProductExpr(ProductExprNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    if (node.children.length == 1)
    {
        return compileValue(cast(ValueNode)node.children[0], vars);
    }
    auto str = "";
    str ~= compileValue(cast(ValueNode)node.children[0], vars);
    Type* leftType = node.children[0].data.get!(Type*);
    Type* rightType;
    for (auto i = 2; i < node.children.length; i += 2)
    {
        str~= "    push   r8\n";
        str ~= compileValue(cast(ValueNode)node.children[i], vars);
        auto op = (cast(ASTTerminal)node.children[i-1]).token;
        rightType = node.children[i].data.get!(Type*);
        if (leftType.isIntegral && rightType.isIntegral)
        {
            str ~= "    pop    r9\n";
            final switch (op)
            {
            case "*":
                str ~= "    imul   r8, r9\n";
                break;
            case "/":
                str ~= "    mov    rax, r9\n"
                // Sign extend rax into rdx, to get rdx:rax
                str ~= "    cqo\n"
                str ~= "    idiv   r8\n";
                // Result of divison lies in rax
                str ~= "    mov    r8, rax\n";
                break;
            case "%":
                str ~= "    mov    rax, r9\n"
                // Sign extend rax into rdx, to get rdx:rax
                str ~= "    cqo\n"
                str ~= "    idiv   r8\n";
                // Remainder lies in rdx
                str ~= "    mov    r8, rdx\n";
                break;
            }
        }
        else
        {
            // Convert either or both to floating point numbers, and also tend
            // to the float vs double size thing
        }
    }
    return str;
}

string compileValue(ValueNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto child = node.children[0];
    auto str = "";
    if (cast(BooleanLiteralNode)child) {
        str ~= compileBooleanLiteral(cast(BooleanLiteralNode)child, vars);
    } else if (cast(LambdaNode)child) {

    } else if (cast(CharLitNode)child) {

    } else if (cast(StringLitNode)child) {
        str ~= compileStringLit(cast(StringLitNode)child, vars);
    } else if (cast(ValueTupleNode)child) {

    } else if (cast(ParenExprNode)child) {

    } else if (cast(ArrayLiteralNode)child) {

    } else if (cast(NumberNode)child) {
        str ~= compileNumber(cast(NumberNode)child, vars);
    } else if (cast(ChanReadNode)child) {

    } else if (cast(IdentifierNode)child) {

    } else if (cast(SliceLengthSentinelNode)child) {

    }

    // TODO handle dotaccess case

    return str;
}

string compileBooleanLiteral(BooleanLiteralNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    auto boolValue = (cast(ASTTerminal)node.children[0]).token;
    if (boolValue == "true")
    {
        str ~= "    mov    r8, 1\n";
    }
    else
    {
        str ~= "    mov    r8, 0\n";
    }
    return str;
}

string compileLambda(LambdaNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileLambdaArgs(LambdaArgsNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileValueTuple(ValueTupleNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileParenExpr(ParenExprNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return compileBoolExpr(cast(BoolExprNode)node.children[0], vars);
}

string compileArrayLiteral(ArrayLiteralNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileNumber(NumberNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    auto child = node.children[0];
    if (cast(IntNumNode)child)
    {
        str ~= compileIntNum(cast(IntNumNode)child, vars);
    }
    else if (cast(FloatNumNode)child)
    {
        str ~= compileFloatNum(cast(FloatNumNode)child, vars);
    }
    return str;
}

string compileCharLit(CharLitNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileStringLit(StringLitNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto stringLit = (cast(ASTTerminal)node.children[0]).token[1..$-1];
    auto label = vars.getUniqDataLabel();
    auto entry = new DataEntry();
    entry.label = label;
    entry.data = DataEntry.toNasmDataString(stringLit);
    vars.dataEntries ~= entry;
    auto str = "";
    // Allocate space for the string with malloc. The size of the string is
    // the size of the refcount section, the size of the string size section,
    // and the size of the string itself rounded up to the nearest power of 2 +
    // 1 for the null byte
    auto strAllocSize = getAllocSize(stringLit.length) + REF_COUNT_SIZE
                                                       + CLAM_STR_SIZE
                                                       + 1;
    str ~= "    ; allocate string, [" ~ ((stringLit.length < 10)
                                        ? stringLit
                                        : (stringLit[0..10])
                                       ) ~ "]\n";
    str ~= "    mov    rdi, " ~ strAllocSize.to!string ~ "\n";
    str ~= "    call   malloc\n";
    // Set the reference count to 1, where the ref count is the first four
    // bytes of the string allocation
    str ~= "    mov    dword [rax], " ~ 1.to!string ~ "\n";
    // Set the length of the string, where the string size location is just
    // past the ref count
    str ~= "    mov    dword [rax+" ~ REF_COUNT_SIZE.to!string ~ "], "
        ~ stringLit.length.to!string ~ "\n";
    str ~= "    push   rax\n";
    // Copy the string from the data section
    str ~= "    mov    rdi, rax\n";
    str ~= "    add    rdi, " ~ (REF_COUNT_SIZE + CLAM_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    mov    rsi, " ~ label ~ "\n";
    str ~= "    mov    rdx, " ~ (stringLit.length + 1).to!string ~ "\n";
    str ~= "    call   memcpy\n";
    str ~= "    pop    rax\n";

    // TODO do something else with values, like... put them on the stack

    // The string value ptr sits in r8
    str ~= "    mov    r8, rax\n";
    return str;
}

string compileIntNum(IntNumNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto num = (cast(ASTTerminal)node.children[0]).token;
    return "    mov    r8, " ~ num ~ "\n";
}

string compileFloatNum(FloatNumNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto num = (cast(ASTTerminal)node.children[0]).token;
    auto label = vars.getUniqDataLabel();
    auto entry = new FloatEntry();
    entry.label = label;
    entry.floatStr = num;
    vars.floatEntries ~= entry;
    return "    movsd    xmm0, [" ~ label ~ "]\n";
}

string compileSliceLengthSentinel(SliceLengthSentinelNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileChanRead(ChanReadNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileTrailer(TrailerNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileDynArrAccess(DynArrAccessNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileTemplateInstanceMaybeTrailer(TemplateInstanceMaybeTrailerNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileFuncCallTrailer(FuncCallTrailerNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileSlicing(SlicingNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileSingleIndex(SingleIndexNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileIndexRange(IndexRangeNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileStartToIndexRange(StartToIndexRangeNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileIndexToEndRange(IndexToEndRangeNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileIndexToIndexRange(IndexToIndexRangeNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileFuncCallArgList(FuncCallArgListNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileDotAccess(DotAccessNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}
