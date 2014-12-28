import std.algorithm;
import std.conv;
import std.stdio;
import std.range;
import parser;
import visitor;
import CodeGenerator;
import typedecl;

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

string compileExpression(BoolExprNode node, FuncVars* vars)
{
    return "";
}

string compileBoolExpr(BoolExprNode node, FuncVars* vars)
{
    return compileOrTest(cast(OrTestNode)node.children[0], vars);
}

string compileOrTest(OrTestNode node, FuncVars* vars)
{
    if (node.children.length == 1)
    {
        return compileAndTest(cast(AndTestNode)node.children[0], vars);
    }
    auto str = "";
    mixin(exprOp("or", "AndTest"));
    return str;
}

string compileAndTest(AndTestNode node, FuncVars* vars)
{
    if (node.children.length == 1)
    {
        return compileNotTest(cast(NotTestNode)node.children[0], vars);
    }
    auto str = "";
    mixin(exprOp("and", "NotTest"));
    return str;
}

string compileNotTest(NotTestNode node, FuncVars* vars)
{
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

string compileComparison(ComparisonNode node, FuncVars* vars)
{
    if (node.children.length == 1)
    {
        return compileExpr(cast(ExprNode)node.children[0], vars);
    }
    return "";
}

string compileExpr(ExprNode node, FuncVars* vars)
{
    return compileOrExpr(cast(OrExprNode)node.children[0], vars);;
}

string compileOrExpr(OrExprNode node, FuncVars* vars)
{
    if (node.children.length == 1)
    {
        return compileXorExpr(cast(XorExprNode)node.children[0], vars);
    }
    auto str = "";
    mixin(exprOp("or", "XorExpr"));
    return str;
}

string compileXorExpr(XorExprNode node, FuncVars* vars)
{
    if (node.children.length == 1)
    {
        return compileAndExpr(cast(AndExprNode)node.children[0], vars);
    }
    auto str = "";
    mixin(exprOp("xor", "AndExpr"));
    return str;
}

string compileAndExpr(AndExprNode node, FuncVars* vars)
{
    if (node.children.length == 1)
    {
        return compileShiftExpr(cast(ShiftExprNode)node.children[0], vars);
    }
    auto str = "";
    mixin(exprOp("and", "ShiftExpr"));
    return str;
}

string compileShiftExpr(ShiftExprNode node, FuncVars* vars)
{
    return compileSumExpr(cast(SumExprNode)node.children[0], vars);
}

string compileSumExpr(SumExprNode node, FuncVars* vars)
{
    if (node.children.length == 1)
    {
        return compileProduct(cast(ProductNode)node.children[0], vars);
    }
    return "";
}

string compileProductExpr(ProductExprNode node, FuncVars* vars)
{
    if (node.children.length == 1)
    {
        return compileValue(cast(ValueNode)node.children[0], vars);
    }
    return "";
}

string compileValue(ValueNode node, FuncVars* vars)
{
    auto child = node.children[0];
    auto str = "";
    if (cast(BooleanLiteralNode)child) {

    } else if (cast(LambdaNode)child) {

    } else if (cast(CharLitNode)child) {

    } else if (cast(StringLitNode)child) {
        str ~= compileStringLit(cast(StringLitNode)child, vars);

        // TODO handle dotaccess case

    } else if (cast(ValueTupleNode)child) {

    } else if (cast(ParenExprNode)child) {

    } else if (cast(ArrayLiteralNode)child) {

    } else if (cast(NumberNode)child) {

    } else if (cast(ChanReadNode)child) {

    } else if (cast(IdentifierNode)child) {

    } else if (cast(SliceLengthSentinelNode)child) {

    }
    return str;
}

string compileBooleanLiteral(BooleanLiteralNode node, FuncVars* vars)
{
    return "";
}

string compileLambda(LambdaNode node, FuncVars* vars)
{
    return "";
}

string compileLambdaArgs(LambdaArgsNode node, FuncVars* vars)
{
    return "";
}

string compileValueTuple(ValueTupleNode node, FuncVars* vars)
{
    return "";
}

string compileParenExpr(ParenExprNode node, FuncVars* vars)
{
    return "";
}

string compileArrayLiteral(ArrayLiteralNode node, FuncVars* vars)
{
    return "";
}

string compileNumber(NumberNode node, FuncVars* vars)
{
    return "";
}

string compileCharLit(CharLitNode node, FuncVars* vars)
{
    return "";
}

string compileStringLit(StringLitNode node, FuncVars* vars)
{
    return "";
}

string compileIntNum(IntNumNode node, FuncVars* vars)
{
    return "";
}

string compileFloatNum(FloatNumNode node, FuncVars* vars)
{
    return "";
}

string compileSliceLengthSentinel(SliceLengthSentinelNode node, FuncVars* vars)
{
    return "";
}

string compileChanRead(ChanReadNode node, FuncVars* vars)
{
    return "";
}

string compileTrailer(TrailerNode node, FuncVars* vars)
{
    return "";
}

string compileDynArrAccess(DynArrAccessNode node, FuncVars* vars)
{
    return "";
}

string compileTemplateInstanceMaybeTrailer(TemplateInstanceMaybeTrailerNode node, FuncVars* vars)
{
    return "";
}

string compileFuncCallTrailer(FuncCallTrailerNode node, FuncVars* vars)
{
    return "";
}

string compileSlicing(SlicingNode node, FuncVars* vars)
{
    return "";
}

string compileSingleIndex(SingleIndexNode node, FuncVars* vars)
{
    return "";
}

string compileIndexRange(IndexRangeNode node, FuncVars* vars)
{
    return "";
}

string compileStartToIndexRange(StartToIndexRangeNode node, FuncVars* vars)
{
    return "";
}

string compileIndexToEndRange(IndexToEndRangeNode node, FuncVars* vars)
{
    return "";
}

string compileIndexToIndexRange(IndexToIndexRangeNode node, FuncVars* vars)
{
    return "";
}

string compileFuncCallArgList(FuncCallArgListNode node, FuncVars* vars)
{
    return "";
}

string compileDotAccess(DotAccessNode node, FuncVars* vars)
{
    return "";
}
