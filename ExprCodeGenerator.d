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
    str ~= compile` ~ descendNode ~ `(`
                    ~ `cast(` ~ descendNode ~ `Node)node.children[0], vars`
                    ~ `);
    for (auto i = 1; i < node.children.length; i++)
    {
        vars.allocateStackSpace(8);
        auto valLoc = vars.getTop.to!string;
        str ~= "    mov    qword [rbp-" ~ valLoc ~ "], r8\n";
        str ~= compile` ~ descendNode ~ `(`
                        ~ `cast(` ~ descendNode ~ `Node)node.children[i], vars`
                        ~ `);
        str ~= "    mov    r9, qword [rbp-" ~ valLoc ~ "]\n";
        vars.deallocateStackSpace(8);
        str ~= "    ` ~ op ~ `    r8, r9\n";
    }
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
    if (cast(NotTestNode)child)
    {
        str ~= compileNotTest(cast(NotTestNode)child, vars);
        str ~= "    not    r8\n";
    }
    else
    {
        str ~= compileComparison(cast(ComparisonNode)child, vars);
    }
    return str;
}

string compileComparison(ComparisonNode node, Context* vars)
{

    // TODO Need to refactor to account for allowing == and != on strings

    debug (COMPILE_TRACE) mixin(tracer);
    if (node.children.length == 1)
    {
        return compileExpr(cast(ExprNode)node.children[0], vars);
    }
    auto op = (cast(ASTTerminal)node.children[1]).token;
    auto str = "";
    str ~= compileExpr(cast(ExprNode)node.children[0], vars);
    vars.allocateStackSpace(8);
    auto valLoc = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ valLoc ~ "], r8\n";
    str ~= compileExpr(cast(ExprNode)node.children[2], vars);
    str ~= "    mov    r9, qword [rbp-" ~ valLoc ~ "]\n";
    vars.deallocateStackSpace(8);
    // Assume that the comparison fails, and update if it succeeds
    str ~= "    mov    r10, 0\n";
    str ~= "    cmp    r9, r8\n";
    auto failureLabel = vars.getUniqLabel();
    // r9 is left value, r8 is right value
    final switch (op)
    {
    case "<=":
        str ~= "    jg     " ~ failureLabel ~ "\n";
        break;
    case ">=":
        str ~= "    jl     " ~ failureLabel ~ "\n";
        break;
    case "<":
        str ~= "    jge    " ~ failureLabel ~ "\n";
        break;
    case ">":
        str ~= "    jle    " ~ failureLabel ~ "\n";
        break;
    case "==":
        str ~= "    jne    " ~ failureLabel ~ "\n";
        break;
    case "!=":
        str ~= "    je     " ~ failureLabel ~ "\n";
        break;
    case "<in>":
        break;
    case "in":
        break;
    }
    str ~= "    mov    r10, 1\n";
    str ~= failureLabel ~ ":\n";
    str ~= "    mov    r8, r10\n";
    return str;
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
    Type* leftType = node.children[0].data["type"].get!(Type*);
    Type* rightType;
    for (auto i = 2; i < node.children.length; i += 2)
    {
        // Left value is in r9, right value is in r8 once both sides are
        // evaluated
        vars.allocateStackSpace(8);
        auto valLoc = vars.getTop.to!string;
        str ~= "    mov    qword [rbp-" ~ valLoc ~ "], r8\n";
        str ~= compileProductExpr(cast(ProductExprNode)node.children[i], vars);
        auto op = (cast(ASTTerminal)node.children[i-1]).token;
        rightType = node.children[i].data["type"].get!(Type*);
        if (leftType.isIntegral && rightType.isIntegral)
        {
            str ~= "    mov    r9, qword [rbp-" ~ valLoc ~ "]\n";
            vars.deallocateStackSpace(8);
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
        else if ((leftType.isFloat || rightType.isFloat)
            && leftType.tag != TypeEnum.ARRAY
            && rightType.tag != TypeEnum.ARRAY)
        {
            str ~= "    mov    r9, qword [rbp-" ~ valLoc ~ "]\n";
            vars.deallocateStackSpace(8);
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
        else
        {
            final switch (op)
            {
            case "~":
                str ~= compileAppendOp(leftType, rightType, vars)
                break;
            }
        }
    }
    return str;
}

string compileAppendOp(Type* leftType, Type* rightType, Context* vars)
{
    // leftType is in r9, rightType is in r8
    auto str = "";
    // If the right type is an array type or a string type, then swap with the
    // left type, so that we only need to write append cases for the following:
    // left    right
    // ----    -----
    // char    char
    // elem    elem
    // string  string
    // string  char
    // array   array
    // array   elem
    if (rightType.tag == TypeEnum.ARRAY || rightType.tag == TypeEnum.STRING)
    {
        str ~= "    xchg   r9, r8\n";
        swap(leftType, rightType);
    }
    // Appending two non-array, non-string types
    if (leftType.tag != TypeEnum.ARRAY && leftType.tag != TypeEnum.STRING
        && rightType.tag != TypeEnum.ARRAY && rightType.tag != TypeEnum.STRING)
    {
        // String special case
        if (leftType.tag == TypeEnum.CHAR)
        {

        }
        // Array case
        else
        {

        }
    }
    else if (leftType.tag == TypeEnum.STRING)
    {
        if (rightType.tag == TypeEnum.STRING)
        {

        }
        // Right type is char
        else
        {

        }
    }
    else if (leftType.tag == TypeEnum.ARRAY)
    {
        // Appending two arrays of the same type
        if (leftType.cmp(rightType))
        {

        }
        // Appending an element of the array type (right) to the
        // array (left)
        else if (leftType.array.arrayType.cmp(rightType))
        {

        }
    }
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
    Type* leftType = node.children[0].data["type"].get!(Type*);
    Type* rightType;
    for (auto i = 2; i < node.children.length; i += 2)
    {
        vars.allocateStackSpace(8);
        auto valLoc = vars.getTop.to!string;
        str ~= "    mov    qword [rbp-" ~ valLoc ~ "], r8\n";
        str ~= compileValue(cast(ValueNode)node.children[i], vars);
        auto op = (cast(ASTTerminal)node.children[i-1]).token;
        rightType = node.children[i].data["type"].get!(Type*);
        if (leftType.isIntegral && rightType.isIntegral)
        {
            str ~= "    mov    r9, qword [rbp-" ~ valLoc ~ "]\n";
            vars.deallocateStackSpace(8);
            final switch (op)
            {
            case "*":
                str ~= "    imul   r8, r9\n";
                break;
            case "/":
                str ~= "    mov    rax, r9\n";
                // Sign extend rax into rdx, to get rdx:rax
                str ~= "    cqo\n";
                str ~= "    idiv   r8\n";
                // Result of divison lies in rax
                str ~= "    mov    r8, rax\n";
                break;
            case "%":
                str ~= "    mov    rax, r9\n";
                // Sign extend rax into rdx, to get rdx:rax
                str ~= "    cqo\n";
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
            assert(false, "Unimplemented");
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
        assert(false, "Unimplemented");
    } else if (cast(CharLitNode)child) {
        assert(false, "Unimplemented");
    } else if (cast(StringLitNode)child) {
        str ~= compileStringLit(cast(StringLitNode)child, vars);
    } else if (cast(ValueTupleNode)child) {
        assert(false, "Unimplemented");
    } else if (cast(ParenExprNode)child) {
        assert(false, "Unimplemented");
    } else if (cast(ArrayLiteralNode)child) {
        str ~= compileArrayLiteral(cast(ArrayLiteralNode)child, vars);
    } else if (cast(NumberNode)child) {
        str ~= compileNumber(cast(NumberNode)child, vars);
    } else if (cast(ChanReadNode)child) {
        assert(false, "Unimplemented");
    } else if (cast(IdentifierNode)child) {
        auto idNode = cast(IdentifierNode)child;
        auto name = getIdentifier(idNode);
        if (vars.isFuncName(name))
        {
            str ~= "    mov    r8, " ~ name ~ "\n";
        }
        else
        {
            str ~= "    ; getting " ~ name ~ "\n";
            str ~= vars.compileVarGet(name);
        }
        if (node.children.length > 1)
        {
            str ~= compileTrailer(cast(TrailerNode)node.children[1], vars);
        }
    } else if (cast(SliceLengthSentinelNode)child) {
        assert(false, "Unimplemented");
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
    auto elemSize = node.children[0].data["type"].get!(Type*).size;
    auto numElems = node.children.length;
    auto allocLength = getAllocSize(numElems);
    // The 8 is the ref count area and the array length area, each 4 bytes
    auto totalAllocSize = allocLength * elemSize + 8;
    auto str = "";
    str ~= "    mov    rdi, " ~ totalAllocSize.to!string ~ "\n";
    str ~= "    call   malloc\n";
    // Set ref count to 1
    str ~= "    mov    dword [rax], 1\n";
    // Set array length to number of elements
    str ~= "    mov    dword [rax+4], " ~ numElems.to!string ~ "\n";
    vars.allocateStackSpace(8);
    auto raxLoc = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ raxLoc ~ "], rax\n";
    foreach (i, child; node.children)
    {
        str ~= compileValue(cast(ValueNode)child, vars);
        str ~= "    mov    rax, qword [rbp-" ~ raxLoc ~ "]\n";
        // Place elements into array past ref count and array size
        str ~= "    mov    " ~ getWordSize(elemSize)
                             ~ " [rax+" ~ (8 + i * elemSize).to!string
                             ~ "], r8" ~ getRRegSuffix(elemSize)
                             ~ "\n";
    }
    vars.deallocateStackSpace(8);
    str ~= "    mov    r8, rax\n";
    return str;
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
    // Set the reference count to 0, where the ref count is the first four bytes
    // of the string allocation. Note that we're setting it to 0 so that
    // optimizations can be made with appends with string and array temporaries.
    // The ref count will be set to 1 when actually assigned to a variable
    str ~= "    mov    dword [rax], 0\n";
    // Set the length of the string, where the string size location is just
    // past the ref count
    str ~= "    mov    dword [rax+" ~ REF_COUNT_SIZE.to!string ~ "], "
        ~ stringLit.length.to!string ~ "\n";
    vars.allocateStackSpace(8);
    str ~= "    mov    qword [rbp-" ~ vars.getTop.to!string ~ "], rax\n";
    // Copy the string from the data section
    str ~= "    mov    rdi, rax\n";
    str ~= "    add    rdi, " ~ (REF_COUNT_SIZE + CLAM_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    mov    rsi, " ~ label ~ "\n";
    str ~= "    mov    rdx, " ~ (stringLit.length + 1).to!string ~ "\n";
    str ~= "    call   memcpy\n";
    str ~= "    mov    rax, qword [rbp-" ~ vars.getTop.to!string ~ "]\n";
    vars.deallocateStackSpace(8);

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
    auto str = "";
    auto child = node.children[0];
    if (cast(DynArrAccessNode)child) {
        str ~= compileDynArrAccess(cast(DynArrAccessNode)child, vars);
    }
    else if (cast(TemplateInstanceMaybeTrailerNode)child) {
        assert(false, "Unimplemented");
    }
    else if (cast(FuncCallTrailerNode)child) {
        str ~= compileFuncCallTrailer(cast(FuncCallTrailerNode)child, vars);
    }
    else if (cast(DotAccessNode)child) {
        assert(false, "Unimplemented");
    }
    return str;
}

string compileDynArrAccess(DynArrAccessNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto arrayType = node.data["parenttype"].get!(Type*);
    auto resultType = node.data["type"].get!(Type*);
    auto str = "";
    // Put the indexed-into variable on the stack
    vars.allocateStackSpace(8);
    auto valLoc = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ valLoc ~ "], r8\n";
    // Check if the slice is a range
    if (arrayType.cmp(resultType))
    {
        // Get the start index in r8 and the end index in r9
        assert(false, "Unimplemented");
    }
    else
    {
        // Get the index in r8
        str ~= compileSlicing(cast(SlicingNode)node.children[0], vars);
        // Get the indexed-into value, so we can index into it
        str ~= "    mov    r10, qword [rbp-" ~ valLoc ~ "]\n";
        // Offset index by type size
        str ~= "    imul   r8, " ~ resultType.size.to!string ~ "\n";
        // Offset index beyond ref count and array length sections
        str ~= "    add    r8, 8\n";
        // Combine the index offset with the address of the start of the array
        str ~= "    add    r8, r10\n";
        // Clear r10 because we might not be moving eight bytes into the reg
        str ~= "    mov    r10, 0\n";
        // Actually grab the value
        str ~= "    mov    r10" ~ getRRegSuffix(resultType.size)
                               ~ ", "
                               ~ getWordSize(resultType.size)
                               ~ " [r8]\n";
        str ~= "    mov    r8, r10\n";
        if (node.children.length > 1)
        {
            str ~= compileTrailer(cast(TrailerNode)node.children[1], vars);
        }
    }
    vars.deallocateStackSpace(8);
    return str;
}

string compileTemplateInstanceMaybeTrailer(TemplateInstanceMaybeTrailerNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileFuncCallTrailer(FuncCallTrailerNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    vars.allocateStackSpace(8);
    auto valLoc = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ valLoc ~ "], r8\n";
    str ~= compileArgList(cast(FuncCallArgListNode)node.children[0], vars);
    str ~= "    mov    r10, qword [rbp-" ~ valLoc ~ "]\n";
    vars.deallocateStackSpace(8);
    str ~= "    call   r10\n";
    return str;
}

string compileSlicing(SlicingNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    auto child = node.children[0];
    if (cast(IndexRangeNode)child) {
        str ~= compileIndexRange(cast(IndexRangeNode)child, vars);
    }
    else if (cast(SingleIndexNode)child) {
        str ~= compileSingleIndex(cast(SingleIndexNode)child, vars);
    }
    return str;
}

string compileSingleIndex(SingleIndexNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return compileBoolExpr(cast(BoolExprNode)node.children[0], vars);
}

string compileIndexRange(IndexRangeNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    assert(false, "Unimplemented");
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

string compileDotAccess(DotAccessNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}

string compileIsExpr(IsExprNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    return "";
}
