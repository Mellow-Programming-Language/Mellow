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
    auto shortCircuitLabel = vars.getUniqLabel;
    auto str = "";
    foreach (child; node.children)
    {
        str ~= compileAndTest(
            cast(AndTestNode)child, vars
        );
        str ~= "    cmp    r8, 0\n";
        str ~= "    jne    " ~ shortCircuitLabel ~ "\n";
    }
    str ~= shortCircuitLabel ~ ":\n";
    return str;
}

string compileAndTest(AndTestNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    if (node.children.length == 1)
    {
        return compileNotTest(cast(NotTestNode)node.children[0], vars);
    }
    auto shortCircuitLabel = vars.getUniqLabel;
    auto str = "";
    foreach (child; node.children)
    {
        str ~= compileNotTest(
            cast(NotTestNode)child, vars
        );
        str ~= "    cmp    r8, 0\n";
        str ~= "    je     " ~ shortCircuitLabel ~ "\n";
    }
    str ~= shortCircuitLabel ~ ":\n";
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
        str ~= "    xor    r8, 1\n";
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
    auto leftType = node.data["lefttype"].get!(Type*);
    auto rightType = node.data["righttype"].get!(Type*);
    if (leftType.isNumeric
        || leftType.tag == TypeEnum.BOOL
        || leftType.tag == TypeEnum.CHAR)
    {
        return compileIntComparison(node, vars);
    }
    else if (leftType.tag == TypeEnum.STRING)
    {
        return compileStringComparison(node, vars);
    }
    else if (rightType.tag == TypeEnum.SET)
    {
        return compileSetComparison(node, vars);
    }
    assert(false, "Unreachable");
}

string compileIntComparison(ComparisonNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
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
    }
    str ~= "    mov    r10, 1\n";
    str ~= failureLabel ~ ":\n";
    str ~= "    mov    r8, r10\n";
    return str;
}

string compileStringComparison(ComparisonNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    vars.runtimeExterns["strcmp"] = true;
    auto op = (cast(ASTTerminal)node.children[1]).token;
    auto str = "";
    str ~= compileExpr(cast(ExprNode)node.children[0], vars);
    vars.allocateStackSpace(8);
    auto valLoc = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ valLoc ~ "], r8\n";
    str ~= compileExpr(cast(ExprNode)node.children[2], vars);
    str ~= "    mov    r9, qword [rbp-" ~ valLoc ~ "]\n";
    vars.deallocateStackSpace(8);
    // r9 is left value, r8 is right value
    // Increment pointers to point at the beginning of the string data, skipping
    // ref count and string length. Since these strings are null-terminated,
    // we can just call strcmp
    str ~= "    add    r8, 8\n";
    str ~= "    add    r9, 8\n";
    str ~= "    mov    rdi, r9\n";
    str ~= "    mov    rsi, r8\n";
    str ~= "    call   strcmp\n";
    // Assume that the comparison fails, and update if it succeeds
    str ~= "    mov    r10, 0\n";
    // strcmp returns an int, so the value we care about is in eax, not rax
    str ~= "    cmp    eax, 0\n";
    auto failureLabel = vars.getUniqLabel();
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
    }
    str ~= "    mov    r10, 1\n";
    str ~= failureLabel ~ ":\n";
    str ~= "    mov    r8, r10\n";
    return str;
}

string compileSetComparison(ComparisonNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
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
        str ~= "    mov    r9, qword [rbp-" ~ valLoc ~ "]\n";
        vars.deallocateStackSpace(8);
        if (leftType.isIntegral && rightType.isIntegral)
        {
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
            assert(false, "Unimplemented");
            final switch (op)
            {
            case "+":
                break;
            case "-":
                break;
            }
        }
        else
        {
            final switch (op)
            {
            case "~":
                // Since the right type is in r8 and the left type is in r9,
                // which is totally confusing, we swap them here
                str ~= "    xchg   r8, r9\n";
                str ~= compileAppendOp(leftType, rightType, vars);
                break;
            }
        }
    }
    return str;
}

// leftType is in r8, rightType is in r9
string compileAppendOp(Type* leftType, Type* rightType, Context* vars)
{
    auto str = "";
    str ~= "    ; append op (~) algorithm start\n";
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
    if ((rightType.tag == TypeEnum.ARRAY || rightType.tag == TypeEnum.STRING)
        && (leftType.tag != TypeEnum.ARRAY && leftType.tag != TypeEnum.STRING))
    {
        str ~= "    xchg   r8, r9\n";
        swap(leftType, rightType);
    }
    // Appending two non-array, non-string types
    if (leftType.tag != TypeEnum.ARRAY && leftType.tag != TypeEnum.STRING
        && rightType.tag != TypeEnum.ARRAY && rightType.tag != TypeEnum.STRING)
    {
        // String special case
        if (leftType.tag == TypeEnum.CHAR)
        {
            assert(false, "Unimplemented");
        }
        // Array case
        else
        {
            assert(false, "Unimplemented");
        }
    }
    else if (leftType.tag == TypeEnum.STRING)
    {
        if (rightType.tag == TypeEnum.STRING)
        {
            str ~= compileStringStringAppend(vars);
        }
        // Right type is char
        else
        {
            assert(false, "Unimplemented");
        }
    }
    else if (leftType.tag == TypeEnum.ARRAY)
    {
        // Appending two arrays of the same type
        if (leftType.cmp(rightType))
        {
            str ~= compileArrayArrayAppend(vars, leftType.array.arrayType.size);
        }
        // Appending an element of the array type (right) to the
        // array (left)
        else if (leftType.array.arrayType.cmp(rightType))
        {
            str ~= compileArrayElemAppend(vars, leftType.array.arrayType.size);
        }
    }
    str ~= "    ; append op (~) algorithm end\n";
    return str;
}

string compileStringStringAppend(Context* vars)
{
    auto str = "";
    auto endRealloc = vars.getUniqLabel();
    // Get size of left string
    str ~= "    mov    r10d, dword [r8+4]\n";
    // Get size of right string
    str ~= "    mov    r11d, dword [r9+4]\n";
    vars.allocateStackSpace(8);
    auto r10Save = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ r10Save ~ "], r10\n";
    // Get the alloc size of left string in r12
    str ~= getAllocSizeAsm("r10", "r12");
    str ~= "    mov    r10, qword [rbp-" ~ r10Save ~ "]\n";
    vars.deallocateStackSpace(8);
    // Get the space left over (leftRemaining) in the left string in r12
    str ~= "    sub    r12, r10\n";
    // pseudo: if (leftRemaining >= rightSize && ((int*)left)[0] == 0)
    str ~= "    cmp    r12, r11\n";
    auto cannotReuseLeft = vars.getUniqLabel();
    str ~= "    jl     " ~ cannotReuseLeft ~ "\n";
    str ~= "    cmp    dword [r8], 0\n";
    str ~= "    jnz    " ~ cannotReuseLeft ~ "\n";
    // Prime rdi with starting address of right section in left string
    str ~= "    mov    rdi, r8\n";
    str ~= "    add    rdi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    add    rdi, r10\n";
    // Prime rsi with right string content
    str ~= "    mov    rsi, r9\n";
    str ~= "    add    rsi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    // Prime rdx with number of bytes to copy, the size of the right
    // string
    str ~= "    mov    rdx, r11\n";
    str ~= compileRegSave(["r8", "r9", "r10", "r11"], vars);
    str ~= "    call   memcpy\n";
    str ~= compileRegRestore(["r8", "r9", "r10", "r11"], vars);
    // Add the size of the right string into the updated left string
    str ~= "    add    dword [r8+4], r11d\n";
    // Re-add a null byte
    str ~= "    mov    r13, r8\n";
    str ~= "    add    r13, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    add    r13, r10\n";
    str ~= "    add    r13, r11\n";
    str ~= "    mov    byte [r13], 0\n";
    // Deallocate right string if necessary
    str ~= "    cmp    dword [r9], 0\n";
    str ~= "    jnz    " ~ endRealloc ~ "\n";
    str ~= "    mov    rdi, r9\n";
    str ~= compileRegSave(["r8"], vars);
    str ~= "    call   free\n";
    str ~= compileRegRestore(["r8"], vars);
    str ~= "    jmp    " ~ endRealloc ~ "\n";
    str ~= cannotReuseLeft ~ ":\n";
    // Get total string size in r13 and r15
    str ~= "    mov    r13, r10\n";
    str ~= "    add    r13, r11\n";
    str ~= "    mov    r15, r13\n";
    // Get string alloc size in r14
    str ~= getAllocSizeAsm("r13", "r14");
    str ~= "    mov    r13, r14\n";
    // Add ref count, string size, and null byte
    str ~= "    add    r13, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE
                               + 1).to!string
                              ~ "\n";
    str ~= "    mov    rdi, r13\n";
    str ~= compileRegSave(["r8", "r9", "r10", "r11"], vars);
    // Get new string allocation in rax
    str ~= "    call   malloc\n";
    str ~= compileRegRestore(["r8", "r9", "r10", "r11"], vars);
    // Set the ref count and string length
    str ~= "    mov    dword [rax], 0\n";
    str ~= "    mov    dword [rax+4], r15d\n";
    // Put the null byte at the end of the string
    str ~= "    mov    r13, r15\n";
    str ~= "    add    r13, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    add    r13, rax\n";
    str ~= "    mov    byte [r13], 0\n";
    // Copy left portion of string into new allocation
    str ~= "    mov    rdi, rax\n";
    str ~= "    add    rdi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    mov    rsi, r8\n";
    str ~= "    add    rsi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    mov    rdx, r10\n";
    str ~= compileRegSave(["r8", "r9", "r10", "r11", "rax"], vars);
    str ~= "    call   memcpy\n";
    str ~= compileRegRestore(["r8", "r9", "r10", "r11", "rax"], vars);
    // Copy right portion of string into new allocation
    str ~= "    mov    rdi, rax\n";
    str ~= "    add    rdi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    add    rdi, r10\n";
    str ~= "    mov    rsi, r9\n";
    str ~= "    add    rsi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    mov    rdx, r11\n";
    str ~= compileRegSave(["r8", "r9", "r10", "r11", "rax"], vars);
    str ~= "    call   memcpy\n";
    str ~= compileRegRestore(["r8", "r9", "r10", "r11", "rax"], vars);
    auto noLeftFree = vars.getUniqLabel();
    // Deallocate left string if necessary
    str ~= "    cmp    dword [r8], 0\n";
    str ~= "    jnz    " ~ noLeftFree ~ "\n";
    str ~= "    mov    rdi, r8\n";
    str ~= compileRegSave(["r9", "rax"], vars);
    str ~= "    call   free\n";
    str ~= compileRegRestore(["r9", "rax"], vars);
    str ~= noLeftFree ~ ":\n";
    // Deallocate right string if necessary
    str ~= "    cmp    dword [r9], 0\n";
    auto endFree = vars.getUniqLabel;
    str ~= "    jnz    " ~ endFree ~ "\n";
    str ~= "    mov    rdi, r9\n";
    str ~= compileRegSave(["rax"], vars);
    str ~= "    call   free\n";
    str ~= compileRegRestore(["rax"], vars);
    str ~= endFree ~ ":\n";
    str ~= "    mov    r8, rax\n";
    str ~= endRealloc ~ ":\n";
    return str;
}

string compileArrayArrayAppend(Context* vars, uint arrayTypeSize)
{
    auto str = "";
    auto endRealloc = vars.getUniqLabel();
    // Get size of left array
    str ~= "    mov    r10d, dword [r8+4]\n";
    // Get size of right array
    str ~= "    mov    r11d, dword [r9+4]\n";
    vars.allocateStackSpace(8);
    auto r10Save = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ r10Save ~ "], r10\n";
    vars.allocateStackSpace(8);
    auto r11Save = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ r11Save ~ "], r11\n";
    // Get number of bytes of data in left array
    str ~= "    imul   r10, " ~ arrayTypeSize.to!string ~ "\n";
    // Get the alloc size of left array in r12. Clobbers r10
    str ~= getAllocSizeAsm("r10", "r12");
    str ~= "    mov    r10, qword [rbp-" ~ r10Save ~ "]\n";
    // Get number of bytes of data in left array
    str ~= "    imul   r10, " ~ arrayTypeSize.to!string ~ "\n";
    // Get the space left over (leftRemaining) in the left array in r12
    str ~= "    sub    r12, r10\n";
    // Get number of bytes of data in right array
    str ~= "    imul   r11, " ~ arrayTypeSize.to!string ~ "\n";
    // pseudo: if (leftRemaining >= rightSize && ((int*)left)[0] == 0)
    str ~= "    cmp    r12, r11\n";
    auto cannotReuseLeft = vars.getUniqLabel();
    str ~= "    jl     " ~ cannotReuseLeft ~ "\n";
    str ~= "    cmp    dword [r8], 0\n";
    str ~= "    jnz    " ~ cannotReuseLeft ~ "\n";
    // Prime rdi with starting address of right section in left array
    str ~= "    mov    rdi, r8\n";
    str ~= "    add    rdi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    add    rdi, r10\n";
    // Prime rsi with right array content
    str ~= "    mov    rsi, r9\n";
    str ~= "    add    rsi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    // Prime rdx with number of bytes to copy, the size of the right
    // array
    str ~= "    mov    rdx, r11\n";
    str ~= compileRegSave(["r8", "r9", "r10", "r11"], vars);
    str ~= "    call   memcpy\n";
    str ~= compileRegRestore(["r8", "r9", "r10", "r11"], vars);
    str ~= "    mov    r11, qword [rbp-" ~ r11Save ~ "]\n";
    // Add the size of the right array into the updated left array
    str ~= "    add    dword [r8+4], r11d\n";
    // Deallocate right array if necessary
    str ~= "    cmp    dword [r9], 0\n";
    str ~= "    jnz    " ~ endRealloc ~ "\n";
    str ~= "    mov    rdi, r9\n";
    str ~= compileRegSave(["r8"], vars);
    str ~= "    call   free\n";
    str ~= compileRegRestore(["r8"], vars);
    str ~= "    jmp    " ~ endRealloc ~ "\n";
    str ~= cannotReuseLeft ~ ":\n";
    // Get total array size in r13 and r15
    str ~= "    mov    r10, qword [rbp-" ~ r10Save ~ "]\n";
    str ~= "    imul   r10, " ~ arrayTypeSize.to!string ~ "\n";
    str ~= "    mov    r11, qword [rbp-" ~ r11Save ~ "]\n";
    str ~= "    imul   r11, " ~ arrayTypeSize.to!string ~ "\n";
    str ~= "    mov    r13, r10\n";
    str ~= "    add    r13, r11\n";
    // Get array alloc size in r14
    str ~= getAllocSizeAsm("r13", "r14");
    str ~= "    mov    r13, r14\n";
    // Add ref count, array size
    str ~= "    add    r13, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    mov    rdi, r13\n";
    str ~= compileRegSave(["r8", "r9", "r10", "r11"], vars);
    // Get new array allocation in rax
    str ~= "    call   malloc\n";
    str ~= compileRegRestore(["r8", "r9", "r10", "r11"], vars);
    // Set the ref count and array length
    str ~= "    mov    dword [rax], 0\n";
    str ~= "    mov    r10, qword [rbp-" ~ r10Save ~ "]\n";
    str ~= "    mov    r11, qword [rbp-" ~ r11Save ~ "]\n";
    str ~= "    mov    dword [rax+4], r10d\n";
    str ~= "    add    dword [rax+4], r11d\n";
    // Copy left portion of array into new allocation
    str ~= "    mov    rdi, rax\n";
    str ~= "    add    rdi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    mov    rsi, r8\n";
    str ~= "    add    rsi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    mov    rdx, r10\n";
    str ~= "    imul   rdx, " ~ arrayTypeSize.to!string ~ "\n";
    str ~= compileRegSave(["r8", "r9", "r10", "r11", "rax"], vars);
    str ~= "    call   memcpy\n";
    str ~= compileRegRestore(["r8", "r9", "r10", "r11", "rax"], vars);
    // Copy right portion of array into new allocation
    str ~= "    mov    r10, qword [rbp-" ~ r10Save ~ "]\n";
    str ~= "    mov    r11, qword [rbp-" ~ r11Save ~ "]\n";
    str ~= "    mov    rdi, rax\n";
    str ~= "    add    rdi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    imul   r10, " ~ arrayTypeSize.to!string ~ "\n";
    str ~= "    add    rdi, r10\n";
    str ~= "    mov    rsi, r9\n";
    str ~= "    add    rsi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    mov    rdx, r11\n";
    str ~= "    imul   rdx, " ~ arrayTypeSize.to!string ~ "\n";
    str ~= compileRegSave(["r8", "r9", "r10", "r11", "rax"], vars);
    str ~= "    call   memcpy\n";
    str ~= compileRegRestore(["r8", "r9", "r10", "r11", "rax"], vars);
    auto noLeftFree = vars.getUniqLabel();
    // Deallocate left array if necessary
    str ~= "    cmp    dword [r8], 0\n";
    str ~= "    jnz    " ~ noLeftFree ~ "\n";
    str ~= "    mov    rdi, r8\n";
    str ~= compileRegSave(["r9", "rax"], vars);
    str ~= "    call   free\n";
    str ~= compileRegRestore(["r9", "rax"], vars);
    str ~= noLeftFree ~ ":\n";
    // Deallocate right array if necessary
    str ~= "    cmp    dword [r9], 0\n";
    auto endFree = vars.getUniqLabel;
    str ~= "    jnz    " ~ endFree ~ "\n";
    str ~= "    mov    rdi, r9\n";
    str ~= compileRegSave(["rax"], vars);
    str ~= "    call   free\n";
    str ~= compileRegRestore(["rax"], vars);
    str ~= endFree ~ ":\n";
    str ~= "    mov    r8, rax\n";
    str ~= endRealloc ~ ":\n";
    vars.deallocateStackSpace(16);
    return str;
}

string compileArrayElemAppend(Context* vars, uint arrayTypeSize)
{
    auto str = "";
    auto endRealloc = vars.getUniqLabel();
    // Get size of left array
    str ~= "    mov    r10d, dword [r8+4]\n";
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto r10Save = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ r10Save ~ "], r10\n";
    // Get number of bytes of data in left array
    str ~= "    imul   r10, " ~ arrayTypeSize.to!string ~ "\n";
    // Get the alloc size of left array in r12. Clobbers r10
    str ~= getAllocSizeAsm("r10", "r12");
    str ~= "    mov    r10, qword [rbp-" ~ r10Save ~ "]\n";
    // Get number of bytes of data in left array
    str ~= "    imul   r10, " ~ arrayTypeSize.to!string ~ "\n";
    // Get the space left over (leftRemaining) in the left array in r12
    str ~= "    sub    r12, r10\n";
    // pseudo: if (leftRemaining != 0 && ((int*)left)[0] == 0)
    str ~= "    cmp    r12, 0\n";
    auto cannotReuseLeft = vars.getUniqLabel();
    str ~= "    jz     " ~ cannotReuseLeft ~ "\n";
    str ~= "    cmp    dword [r8], 0\n";
    str ~= "    jnz    " ~ cannotReuseLeft ~ "\n";
    // Prime rdi with starting address of right section in left array
    str ~= "    mov    rdi, r8\n";
    str ~= "    add    rdi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    add    rdi, r10\n";
    str ~= "    mov    " ~ getWordSize(arrayTypeSize)
                         ~ " [rdi], r9"
                         ~ getRRegSuffix(arrayTypeSize)
                         ~ "\n";
    // Increase size of array by 1
    str ~= "    add    dword [r8+4], 1\n";
    str ~= "    jmp    " ~ endRealloc ~ "\n";
    str ~= cannotReuseLeft ~ ":\n";
    // Get total array size in r13
    str ~= "    mov    r10, qword [rbp-" ~ r10Save ~ "]\n";
    str ~= "    imul   r10, " ~ arrayTypeSize.to!string ~ "\n";
    str ~= "    mov    r13, r10\n";
    str ~= "    add    r13, " ~ arrayTypeSize.to!string ~ "\n";
    // Get array alloc size in r14
    str ~= getAllocSizeAsm("r13", "r14");
    str ~= "    mov    r13, r14\n";
    // Add ref count, array size
    str ~= "    add    r13, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    mov    rdi, r13\n";
    str ~= compileRegSave(["r8", "r9", "r10", "r11"], vars);
    // Get new array allocation in rax
    str ~= "    call   malloc\n";
    str ~= compileRegRestore(["r8", "r9", "r10", "r11"], vars);
    // Set the ref count and array length
    str ~= "    mov    dword [rax], 0\n";
    str ~= "    mov    r10, qword [rbp-" ~ r10Save ~ "]\n";
    str ~= "    mov    dword [rax+4], r10d\n";
    str ~= "    add    dword [rax+4], 1\n";
    // Copy left portion of array into new allocation
    str ~= "    mov    rdi, rax\n";
    str ~= "    add    rdi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    mov    rsi, r8\n";
    str ~= "    add    rsi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    mov    rdx, r10\n";
    str ~= "    imul   rdx, " ~ arrayTypeSize.to!string ~ "\n";
    str ~= compileRegSave(["r8", "r9", "r10", "r11", "rax"], vars);
    str ~= "    call   memcpy\n";
    str ~= compileRegRestore(["r8", "r9", "r10", "r11", "rax"], vars);
    // Copy right value into new allocation
    str ~= "    mov    r10, qword [rbp-" ~ r10Save ~ "]\n";
    str ~= "    mov    rdi, rax\n";
    str ~= "    add    rdi, " ~ (REF_COUNT_SIZE
                               + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    imul   r10, " ~ arrayTypeSize.to!string ~ "\n";
    str ~= "    add    rdi, r10\n";
    str ~= "    mov    " ~ getWordSize(arrayTypeSize)
                         ~ " [rdi], r9"
                         ~ getRRegSuffix(arrayTypeSize)
                         ~ "\n";
    auto noLeftFree = vars.getUniqLabel();
    // Deallocate left array if necessary
    str ~= "    cmp    dword [r8], 0\n";
    str ~= "    jnz    " ~ noLeftFree ~ "\n";
    str ~= "    mov    rdi, r8\n";
    str ~= compileRegSave(["r9", "rax"], vars);
    str ~= "    call   free\n";
    str ~= compileRegRestore(["r9", "rax"], vars);
    str ~= noLeftFree ~ ":\n";
    str ~= "    mov    r8, rax\n";
    str ~= endRealloc ~ ":\n";
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
    auto type = node.data["type"].get!(Type*);
    auto child = node.children[0];
    auto str = "";
    if (cast(BooleanLiteralNode)child) {
        str ~= compileBooleanLiteral(cast(BooleanLiteralNode)child, vars);
    } else if (cast(LambdaNode)child) {
        assert(false, "Unimplemented");
    } else if (cast(StructConstructorNode)child) {
        str ~= compileStructConstructor(cast(StructConstructorNode)child, vars);
    } else if (cast(CharLitNode)child) {
        str ~= compileCharLit(cast(CharLitNode)child, vars);
    } else if (cast(StringLitNode)child) {
        str ~= compileStringLit(cast(StringLitNode)child, vars);
    } else if (cast(ValueTupleNode)child) {
        assert(false, "Unimplemented");
    } else if (cast(ParenExprNode)child) {
        str ~= compileParenExpr(cast(ParenExprNode)child, vars);
    } else if (cast(ArrayLiteralNode)child) {
        str ~= compileArrayLiteral(cast(ArrayLiteralNode)child, vars);
    } else if (cast(NumberNode)child) {
        str ~= compileNumber(cast(NumberNode)child, vars);
    } else if (cast(ChanReadNode)child) {
        str ~= compileChanRead(cast(ChanReadNode)child, vars);
    } else if (cast(IdentifierNode)child) {
        auto idNode = cast(IdentifierNode)child;
        auto name = getIdentifier(idNode);
        if (vars.isVarName(name))
        {
            vars.valueTag = "var";
            str ~= "    ; getting " ~ name ~ "\n";
            str ~= vars.compileVarGet(name);
        }
        else if (vars.isFuncName(name))
        {
            vars.valueTag = "func";
            str ~= "    mov    r8, " ~ name ~ "\n";
        }
        else if (type.tag == TypeEnum.VARIANT)
        {
            vars.valueTag = "variant";
            str ~= "    ; instantiating constructor " ~ name
                                                      ~ "\n";
            str ~= "    mov    rdi, " ~ type.variantDef
                                            .getVariantAllocSize
                                            .to!string
                                      ~ "\n";
            str ~= "    call   malloc\n";
            // Set the variant tag
            str ~= "    mov    dword [rax+4], " ~ type.variantDef
                                                      .getMemberIndex(name)
                                                      .to!string
                                                ~ "\n";
            str ~= "    mov    r8, rax\n";
        }
        if (node.children.length > 1)
        {
            str ~= compileTrailer(cast(TrailerNode)node.children[1], vars);
        }
    } else if (cast(SliceLengthSentinelNode)child) {
        str ~= compileSliceLengthSentinel(
            cast(SliceLengthSentinelNode)child,
            vars
        );
    }

    // Handle dotaccess
    if (node.children.length > 1 &&
        (
            cast(BooleanLiteralNode)child ||
            cast(CharLitNode)child ||
            cast(StringLitNode)child ||
            cast(ParenExprNode)child ||
            cast(ArrayLiteralNode)child ||
            cast(NumberNode)child ||
            cast(ChanReadNode)child
        ))
    {
        str ~= compileDotAccess(cast(DotAccessNode)node.children[1], vars);
    }

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

string compileStructConstructor(StructConstructorNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    auto structDef = node.data["type"].get!(Type*).structDef;
    Type*[string] members;
    foreach (member; structDef.members)
    {
        members[member.name] = member.type;
    }
    str ~= "    mov    rdi, " ~ getStructAllocSize(structDef).to!string
                              ~ "\n";
    str ~= "    call   malloc\n";
    // Set the refcount to 1, as we're assigning this struct to a variable
    str ~= "    mov    dword [rax], 1\n";
    str ~= "    mov    r8, rax\n";
    vars.allocateStackSpace(8);
    auto structLoc = vars.getTop.to!string;
    scope (exit) vars.deallocateStackSpace(8);
    str ~= "    mov    qword [rbp-" ~ structLoc
                                    ~ "], r8\n";
    auto i = 1;
    if (cast(TemplateInstantiationNode)node.children[1])
    {
        i = 2;
    }
    for (; i < node.children.length; i += 2)
    {
        auto memberName = getIdentifier(cast(IdentifierNode)node.children[i]);
        auto memberOffset = structDef.getOffsetOfMember(memberName);
        auto type = members[memberName];
        str ~= compileBoolExpr(cast(BoolExprNode)node.children[i+1], vars);
        str ~= "    mov    r10, qword [rbp-" ~ structLoc
                                            ~ "]\n";
        // r10 is now a pointer to the beginning of the member of the struct
        str ~= "    add    r10, " ~ (REF_COUNT_SIZE
                                   + STRUCT_BUFFER_SIZE
                                   + memberOffset).to!string
                                  ~ "\n";
        if (type.size <= 8)
        {
            str ~= "    mov    " ~ getWordSize(type.size)
                                 ~ " [r10], r8"
                                 ~ getRRegSuffix(type.size)
                                 ~ "\n";
        }
        // Function pointer case
        else
        {

        }
    }
    str ~= "    mov    r8, qword [rbp-" ~ structLoc
                                        ~ "]\n";
    return str;
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
    auto elemSize = 0;
    if (node.children.length > 0)
    {
        elemSize = node.children[0].data["type"].get!(Type*).size;
    }
    auto numElems = node.children.length;
    auto allocLength = getAllocSize(numElems);
    // The 8 is the ref count area and the array length area, each 4 bytes
    auto totalAllocSize = allocLength * elemSize + 8;
    auto str = "";
    str ~= "    mov    rdi, " ~ totalAllocSize.to!string ~ "\n";
    str ~= "    call   malloc\n";
    // Set the reference count to 0, where the ref count is the first four bytes
    // of the array allocation. Note that we're setting it to 0 so that
    // optimizations can be made with appends with string and array temporaries.
    // The ref count will be set to 1 when actually assigned to a variable
    str ~= "    mov    dword [rax], 0\n";
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

    // TODO add in support for octal and hex characters

    auto charLit = (cast(ASTTerminal)node.children[0]).token[1..$-1];
    char code = getChar(charLit);
    auto str = "";
    str ~= "    mov    r8, " ~ (cast(int)code).to!string
                             ~ "\n";
    return str;
}

string compileStringLit(StringLitNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto stringLit = (cast(ASTTerminal)node.children[0]).token[1..$-1];
    auto strTrueLength = 0;
    for (auto i = 0; i < stringLit.length; i++)
    {
        strTrueLength++;
        if (stringLit[i] == '\\')
        {
            i++;
        }
    }
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
    auto strAllocSize = getAllocSize(strTrueLength) + REF_COUNT_SIZE
                                                    + MELLOW_STR_SIZE
                                                    + 1;
    str ~= "    ; allocate string, [" ~ ((strTrueLength < 10)
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
        ~ strTrueLength.to!string ~ "\n";
    vars.allocateStackSpace(8);
    str ~= "    mov    qword [rbp-" ~ vars.getTop.to!string ~ "], rax\n";
    // Copy the string from the data section
    str ~= "    mov    rdi, rax\n";
    str ~= "    add    rdi, " ~ (REF_COUNT_SIZE + MELLOW_STR_SIZE).to!string
                              ~ "\n";
    str ~= "    mov    rsi, " ~ label ~ "\n";
    str ~= "    mov    rdx, " ~ (strTrueLength + 1).to!string ~ "\n";
    str ~= "    call   memcpy\n";
    str ~= "    mov    rax, qword [rbp-" ~ vars.getTop.to!string ~ "]\n";
    vars.deallocateStackSpace(8);
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
    // Get the length from the __ZZlengthSentinel bss location
    return "    mov    r8, qword [__ZZlengthSentinel]\n";
}

string compileChanRead(ChanReadNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    vars.runtimeExterns["yield"] = true;
    auto str = "";
    auto valSize = node.data["type"].get!(Type*).size;
    str ~= compileBoolExpr(cast(BoolExprNode)node.children[0], vars);
    vars.allocateStackSpace(8);
    auto chanLoc = vars.getTop;
    auto tryRead = vars.getUniqLabel;
    auto cannotRead = vars.getUniqLabel;
    auto successfulRead = vars.getUniqLabel;
    // Channel is in r8
    str ~= tryRead ~ ":\n";
    str ~= "    ; Test if the channel has a valid value in it.\n";
    str ~= "    ; Yield if no, read if yes\n";
    str ~= "    cmp    dword [r8+4], 0\n";
    str ~= "    jz     " ~ cannotRead
                         ~ "\n";
    str ~= "    mov    r9" ~ getRRegSuffix(valSize)
                           ~ ", "
                           ~ getWordSize(valSize)
                           ~ " [r8+8]\n";
    // Invalidate the data in the channel
    str ~= "    mov    dword [r8+4], 0\n";
    str ~= "    mov    r8, r9\n";
    str ~= "    jmp    " ~ successfulRead
                         ~ "\n";
    str ~= cannotRead ~ ":\n";
    // Store channel on stack, then yield
    str ~= "    mov    qword [rbp-" ~ chanLoc.to!string
                                    ~ "], r8\n";
    str ~= "    call   yield\n";
    // Restore channel and value, reattempt write
    str ~= "    mov    r8, qword [rbp-" ~ chanLoc.to!string
                                        ~ "]\n";
    str ~= "    jmp    " ~ tryRead
                         ~ "\n";
    str ~= successfulRead ~ ":\n";
    vars.deallocateStackSpace(8);
    return str;
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
        str ~= compileTemplateInstanceMaybeTrailer(
            cast(TemplateInstanceMaybeTrailerNode)child,
            vars
        );
    }
    else if (cast(FuncCallTrailerNode)child) {
        str ~= compileFuncCallTrailer(cast(FuncCallTrailerNode)child, vars);
    }
    else if (cast(DotAccessNode)child) {
        str ~= compileDotAccess(cast(DotAccessNode)child, vars);
    }
    return str;
}

string compileDynArrAccess(DynArrAccessNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);

    // TODO implement string range indexing. Currently only string single
    // indexing works, to yield a char

    auto arrayType = node.data["parenttype"].get!(Type*);
    auto indexType = node.data["type"].get!(Type*);
    Type* resultType;
    if (arrayType.tag == TypeEnum.ARRAY)
    {
        resultType = arrayType.array.arrayType;
    }
    else if (arrayType.tag == TypeEnum.STRING)
    {
        auto charType = new Type();
        charType.tag = TypeEnum.CHAR;
        resultType = charType;
    }
    auto str = "";
    vars.bssQWordAllocs["__ZZlengthSentinel"] = true;

    // TODO this doesn't hold up to recursive array accesses. An array
    // index access inside of an array index access will overwrite the
    // length sentinel for the parent access, and then it will be invalid
    // for the rest of the calculation once the inner access is exited.
    // As in: arr[$-arr2[$-1]+$/2], the second arr $ (the third $ overall)
    // is now invalid

    // Get length of array in r9, and store it in the bss __ZZlengthSentinel loc
    str ~= "    mov    r9d, dword [r8+4]\n";
    str ~= "    mov    qword [__ZZlengthSentinel], r9\n";
    // Put the indexed-into variable on the stack
    vars.allocateStackSpace(8);
    auto valLoc = vars.getTop.to!string;
    scope (exit) vars.deallocateStackSpace(8);
    str ~= "    mov    qword [rbp-" ~ valLoc ~ "], r8\n";
    // Check if the slice is a range
    if (arrayType.cmp(indexType))
    {
        // Since we're getting a range, we need to allocate and populate a new
        // array with the range of values from the sliced array.
        // Get the start index in r8 and the end index in r9
        str ~= compileSlicing(cast(SlicingNode)node.children[0], vars);
        // Store just the start index, for when we need to memcpy
        vars.allocateStackSpace(8);
        auto startIndexLoc = vars.getTop.to!string;
        str ~= "    mov    qword [rbp-" ~ startIndexLoc ~ "], r8\n";
        scope (exit) vars.deallocateStackSpace(8);
        auto nonsenseSliceLabel = vars.getUniqLabel;
        auto sliceEndLabel = vars.getUniqLabel;
        auto acceptableEndIndexLabel = vars.getUniqLabel;
        // Compare start index to size of original array, and if it's larger,
        // allocate an empty array
        str ~= "    mov    r10, qword [rbp-" ~ valLoc ~ "]\n";
        str ~= "    mov    r10d, dword [r10+4]\n";
        str ~= "    cmp    r10, r8\n";
        str ~= "    jbe    " ~ nonsenseSliceLabel ~ "\n";
        // Force the end index to be within the bounds of the array
        str ~= "    cmp    r10, r9\n";
        str ~= "    jae    " ~ acceptableEndIndexLabel ~ "\n";
        str ~= "    mov    r9, r10\n";
        str ~= acceptableEndIndexLabel ~ ":\n";
        // The start index is within the bounds of the array, so get the total
        // size of the slice
        str ~= "    mov    r10, r9\n";
        str ~= "    sub    r10, r8\n";
        // If the slice size is negative or zero, allocate empty array
        str ~= "    jbe    " ~ nonsenseSliceLabel ~ "\n";
        // Store the length of the slice in a callee-saved register
        str ~= "    mov    r12, r10\n";
        // Get the alloc size of the slice
        str ~= getAllocSizeAsm("r10", "rdi");
        // Multiply the alloc size by the element size
        str ~= "    imul   rdi, " ~ resultType.size.to!string ~ "\n";
        // Add 8 for the ref count and array size
        str ~= "    add    rdi, 8\n";
        if (arrayType.tag == TypeEnum.STRING)
        {
            // Add the null byte to the memory allocation
            str ~= "    add    rdi, 1\n";
        }
        // Get the allocated memory pointer in rax
        str ~= "    call   malloc\n";
        // Store the new allocation pointer
        vars.allocateStackSpace(8);
        auto newAllocLoc = vars.getTop.to!string;
        str ~= "    mov    qword [rbp-" ~ newAllocLoc ~ "], rax\n";
        scope (exit) vars.deallocateStackSpace(8);
        // Set the ref-count to 0
        str ~= "    mov    dword [rax], 0\n";
        // Set the array length
        str ~= "    mov    dword [rax+4], r12d\n";
        // Get the original array pointer
        str ~= "    mov    r10, qword [rbp-" ~ valLoc ~ "]\n";
        // memcpy the slice into the new memory allocation
        str ~= "    mov    rdi, rax\n";
        str ~= "    add    rdi, 8\n";
        // Get the start index value
        str ~= "    mov    rsi, qword [rbp-" ~ startIndexLoc ~ "]\n";
        str ~= "    imul   rsi, " ~ resultType.size.to!string ~ "\n";
        str ~= "    add    rsi, 8\n";
        str ~= "    add    rsi, r10\n";
        str ~= "    mov    rdx, r12\n";
        str ~= "    imul   rdx, " ~ resultType.size.to!string ~ "\n";
        str ~= "    call   memcpy\n";
        // Add the actual null byte into the memory location
        if (arrayType.tag == TypeEnum.STRING)
        {
            // memcpy returns the destination pointer in rax, so we have
            // a pointer to the beginning of the actual data (past the refcount
            // and size). r12 is a callee saved register, so we still have the
            // string length in hand. Characters are a single byte, so adding
            // the length to the pointer yields where the null byte needs to go
            str ~= "    add    rax, r12\n";
            str ~= "    mov    byte [rax], 0\n";
        }
        str ~= "    mov    r8, qword [rbp-" ~ newAllocLoc ~ "]\n";
        str ~= "    jmp    " ~ sliceEndLabel ~ "\n";
        // If we're dealing with a "nonsense" slice, then create an array of
        // size zero with zero elements and no allocation for data (1 byte for
        // null byte if string)
        str ~= nonsenseSliceLabel ~ ":\n";
        str ~= "    mov    rdi, 0\n";
        // Add 8 for the ref count and array size
        str ~= "    add    rdi, 8\n";
        if (arrayType.tag == TypeEnum.STRING)
        {
            // Add the null byte to the memory allocation
            str ~= "    add    rdi, 1\n";
        }
        // Get the allocated memory pointer in rax
        str ~= "    call   malloc\n";
        // Store the new allocation pointer
        vars.allocateStackSpace(8);
        auto emptyAllocLoc = vars.getTop.to!string;
        str ~= "    mov    qword [rbp-" ~ emptyAllocLoc ~ "], rax\n";
        scope (exit) vars.deallocateStackSpace(8);
        // Set the ref-count to 0
        str ~= "    mov    dword [rax], 0\n";
        // Set the array length to 0
        str ~= "    mov    dword [rax+4], 0\n";
        // Place a null byte into the single data byte allocated, if a string
        if (arrayType.tag == TypeEnum.STRING)
        {
            str ~= "    mov    byte [rax+8], 0\n";
        }
        str ~= "    mov    r8, qword [rbp-" ~ emptyAllocLoc ~ "]\n";
        str ~= sliceEndLabel ~ ":\n";
    }
    else
    {
        // Get the index in r8
        str ~= compileSlicing(cast(SlicingNode)node.children[0], vars);
        // Get the indexed-into value, so we can index into it
        str ~= "    mov    r10, qword [rbp-" ~ valLoc ~ "]\n";
        if (!vars.release)
        {
            vars.runtimeExterns["printf"] = true;
            // Get the array size; we're going to do an index out-of-bounds
            // check! First, get the array size
            str ~= "    mov    r11d, dword [r10+4]\n";
            // Now, compare the array size to the index value
            auto inBoundsLabel = vars.getUniqLabel;
            str ~= "    cmp    r11, r8\n";
            // If we're within bounds, jump to continuing with the access...
            str ~= "    jg     " ~ inBoundsLabel ~ "\n";
            // Otherwise, print an assert error and hard exit!
            auto assertLabel = vars.getUniqDataLabel();
            auto entry = new DataEntry();
            entry.label = assertLabel;
            entry.data = DataEntry.toNasmDataString(
                "Assert Error: Array index out-of-bounds: " ~ errorHeader(node)
                                                            ~ "\\n"
            );
            vars.dataEntries ~= entry;
            str ~= "    mov    rdi, " ~ assertLabel ~ "\n";
            str ~= "    call   printf\n";
            str ~= "    mov    rdi, 1\n";
            str ~= "    call   exit\n";
            str ~= inBoundsLabel ~ ":\n";
        }
        // Offset index by type size
        str ~= "    imul   r8, " ~ resultType.size.to!string ~ "\n";
        // Offset index beyond ref count and array length sections
        str ~= "    add    r8, 8\n";
        // Combine the index offset with the address of the start of the array
        str ~= "    add    r8, r10\n";
        // Clear r10 because we might not be moving eight bytes into the reg
        str ~= "    mov    r10, 0\n";
        // Actually grab the value
        if (resultType.needsSignExtend)
        {
            str ~= "    movsx  r10, " ~ getWordSize(resultType.size)
                                      ~ " [r8]\n";
        }
        else
        {
            str ~= "    mov    r10" ~ getRRegSuffix(resultType.size)
                                    ~ ", "
                                    ~ getWordSize(resultType.size)
                                    ~ " [r8]\n";
        }
        str ~= "    mov    r8, r10\n";
    }
    if (node.children.length > 1)
    {
        str ~= compileTrailer(cast(TrailerNode)node.children[1], vars);
    }
    return str;
}

string compileTemplateInstanceMaybeTrailer(
    TemplateInstanceMaybeTrailerNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    // The template instantiation is a purely typechecking issue, so just jump
    // straight to the trailer if there is one
    if (node.children.length > 1)
    {
        str ~= compileTrailer(cast(TrailerNode)node.children[1], vars);
    }
    return str;
}

string compileFuncCallTrailer(FuncCallTrailerNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    final switch (vars.valueTag)
    {
    case "func":
        auto funcSig = node.data["funcsig"].get!(FuncSig*);
        vars.allocateStackSpace(8);
        auto valLoc = vars.getTop.to!string;
        str ~= "    mov    qword [rbp-" ~ valLoc ~ "], r8\n";
        str ~= compileArgList(cast(FuncCallArgListNode)node.children[0], vars);
        str ~= "    mov    r10, qword [rbp-" ~ valLoc ~ "]\n";
        vars.deallocateStackSpace(8);
        if (funcSig.returnType.tag == TypeEnum.TUPLE)
        {
            // Allocate stack space for every return value beyond the first,
            // which will be returned in rax, to be returned on the stack
            auto alignedSize = funcSig.returnType
                                      .tuple
                                      .types[1..$]
                                      .map!(a => a.size)
                                      .array
                                      .getAlignedSize;
            str ~= "    sub    rsp, " ~ (alignedSize
                                       + getPadding(alignedSize, 16))
                                        .to!string
                                      ~ "\n";
            // In the assignment statement that actually deals with assigning
            // the value, we'll check if the value was from a function call,
            // and if it was, we'll check if it returned a tuple, and if it
            // was, we'll grab the values off the stack and fix the stack
        }
        str ~= "    call   r10\n";
        str ~= "    mov    r8, rax\n";
        break;
    case "variant":
        str ~= compileArgList(cast(FuncCallArgListNode)node.children[0], vars);
        break;
    }
    if (node.children.length > 1)
    {
        str ~= compileTrailer(cast(TrailerNode)node.children[1], vars);
    }
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
    vars.bssQWordAllocs["__ZZlengthSentinel"] = true;
    return compileBoolExpr(cast(BoolExprNode)node.children[0], vars);
}

string compileIndexRange(IndexRangeNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto child = node.children[0];
    auto str = "";
    if (cast(StartToIndexRangeNode)child) {
        str ~= compileStartToIndexRange(cast(StartToIndexRangeNode)child, vars);
    }
    else if (cast(IndexToIndexRangeNode)child) {
        str ~= compileIndexToIndexRange(cast(IndexToIndexRangeNode)child, vars);
    }
    else if (cast(IndexToEndRangeNode)child) {
        str ~= compileIndexToEndRange(cast(IndexToEndRangeNode)child, vars);
    }
    return str;
}

string compileStartToIndexRange(StartToIndexRangeNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    // Get the end index in r8, but we want it in r9 and 0 to be in r8
    str ~= compileBoolExpr(cast(BoolExprNode)node.children[0], vars);
    str ~= "    mov    r9, 0\n";
    str ~= "    xchg   r8, r9\n";
    return str;
}

string compileIndexToEndRange(IndexToEndRangeNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto str = "";
    // Get the start index in r8
    str ~= compileBoolExpr(cast(BoolExprNode)node.children[0], vars);
    // Get the end index from the __ZZlengthSentinel bss loc
    str ~= "    mov    r9, qword [__ZZlengthSentinel]\n";
    return str;
}

string compileIndexToIndexRange(IndexToIndexRangeNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    // The start index is expected to be in r8, and the end index is
    // expected to be in r9
    auto str = "";
    vars.allocateStackSpace(8);
    auto startLoc = vars.getTop.to!string;
    scope (exit) vars.deallocateStackSpace(8);
    str ~= compileBoolExpr(cast(BoolExprNode)node.children[0], vars);
    str ~= "    mov    qword [rbp-" ~ startLoc
                                    ~ "], r8\n";
    str ~= compileBoolExpr(cast(BoolExprNode)node.children[1], vars);
    str ~= "    mov    r9, r8\n";
    str ~= "    mov    r8, qword [rbp-" ~ startLoc
                                        ~ "]\n";
    return str;
}

string compileDotAccess(DotAccessNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto accessedType = node.data["type"].get!(Type*);
    auto id = getIdentifier(cast(IdentifierNode)node.children[0]);
    auto str = "";
    str ~= "    ; dot access on type [" ~ accessedType.format
                                       ~ "]: "
                                       ~ id
                                       ~ "\n";
    if (accessedType.tag == TypeEnum.ARRAY
        || accessedType.tag == TypeEnum.STRING)
    {
        if (id == "length")
        {
            // Grab the length of the string or array and throw it back into r8
            str ~= "    mov    r8d, dword [r8+4]\n";
        }
    }
    else if (accessedType.tag == TypeEnum.STRUCT)
    {
        auto member = accessedType.structDef
                                  .getMember(id);
        auto memberOffset = accessedType.structDef
                                        .getOffsetOfMember(id);
        auto memberSize = member.type.size;
        // r8 is now a pointer to the beginning of the member of the struct
        str ~= "    add    r8, " ~ (REF_COUNT_SIZE
                                  + STRUCT_BUFFER_SIZE
                                  + memberOffset).to!string
                                 ~ "\n";
        // If it's not an 8-byte or 4-byte mov, we need to zero the target
        // register
        if (memberSize < 4)
        {
            str ~= "    mov    r9, 0\n";
        }
        str ~= "    mov    r9" ~ getRRegSuffix(memberSize)
                               ~ ", "
                               ~ getWordSize(memberSize)
                               ~ "[r8]\n";
        str ~= "    mov    r8, r9\n";
        if (node.children.length > 1)
        {
            str ~= compileTrailer(cast(TrailerNode)node.children[1], vars);
        }
    }
    else
    {
        assert(false, "Unimplemented");
    }
    return str;
}

string compileIsExpr(IsExprNode node, Context* vars)
{
    debug (COMPILE_TRACE) mixin(tracer);
    auto variantType = node.data["type"].get!(Type*);
    auto constructorName = node.data["constructor"].get!(string);
    auto member = variantType.variantDef
                             .getMember(constructorName);
    auto memberTag = variantType.variantDef
                                .getMemberIndex(constructorName);
    auto str = "";
    str ~= compileBoolExpr(cast(BoolExprNode)node.children[0], vars);
    // We now have the variant pointer in hand in r8
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto variantLoc = vars.getTop.to!string;
    str ~= "    mov    [rbp-" ~ variantLoc
                              ~ "], r8\n";
    auto wrongTag = vars.getUniqLabel;
    auto end = vars.getUniqLabel;
    // Get the variant tag
    str ~= "    mov    r9d, dword [r8+4]\n";
    str ~= "    cmp    r9, " ~ memberTag.to!string
                             ~ "\n";
    str ~= "    jne    " ~ wrongTag
                         ~ "\n";
    if (node.children.length > 2)
    {
        auto memberTypes = member.constructorElems.tuple.types;
        auto memberTypeSizes = memberTypes.map!(a => a.size)
                                          .array;
        foreach (i, child; node.children[2..$])
        {
            if (cast(IdentifierNode)child)
            {
                auto varName = getIdentifier(cast(IdentifierNode)child);
                auto memberOffset = memberTypeSizes.getAlignedIndexOffset(i);
                auto valueSize = memberTypeSizes[i];
                auto pair = new VarTypePair();
                pair.varName = varName;
                pair.type = memberTypes[i];
                vars.addStackVar(pair);
                switch (valueSize)
                {
                case 16:
                    assert(false, "Unimplemented");
                    break;
                case 1:
                case 2:
                    // mov's of size 4 automatically zero the upper 4 bytes of
                    // the register, but smaller mov sizes don't
                    str ~= "    mov    r9, 0\n";
                case 4:
                case 8:
                default:
                    str ~= "    mov    r8, [rbp-" ~ variantLoc
                                                  ~ "]\n";
                    str ~= "    mov    r9" ~ getRRegSuffix(valueSize)
                                           ~ ", "
                                           ~ getWordSize(valueSize)
                                           ~ " [r8+"
                                           ~ (REF_COUNT_SIZE
                                            + VARIANT_TAG_SIZE
                                            + memberOffset).to!string
                                           ~ "]\n";
                    str ~= "    mov    [rbp-" ~ variantLoc
                                              ~ "], r8\n";
                    str ~= "    mov    r8, r9\n";
                    str ~= vars.compileVarSet(varName);
                    break;
                }
            }
        }
    }
    // The is expression succeeded, so set a true bool in r8
    str ~= "    mov    r8, 1\n";
    str ~= "    jmp    " ~ end
                         ~ "\n";
    str ~= wrongTag ~ ":\n";
    // The is expression failed, so set a false bool in r8
    str ~= "    mov    r8, 0\n";
    str ~= end ~ ":\n";
    return str;
}
