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
        if (leftType.isIntegral && rightType.isIntegral && op != "~")
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
        else if ((leftType.isFloat || rightType.isFloat) && op != "~")
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
        leftType = node.children[i-1].data["type"].get!(Type*);
    }
    return str;
}

// leftType is in r8, rightType is in r9
string compileAppendOp(Type* leftType, Type* rightType, Context* vars)
{
    vars.runtimeExterns["__arr_arr_append"] = true;
    vars.runtimeExterns["__elem_elem_append"] = true;
    vars.runtimeExterns["__elem_arr_append"] = true;
    vars.runtimeExterns["__arr_elem_append"] = true;
    auto str = "";
    str ~= "    ; append op (~) algorithm start\n";
    // Appending two non-array, non-string types. This means left and right
    // must be the same type, as well
    if (leftType.tag != TypeEnum.ARRAY && leftType.tag != TypeEnum.STRING
        && rightType.tag != TypeEnum.ARRAY && rightType.tag != TypeEnum.STRING)
    {
        str ~= "    mov     rdi, r8\n";
        str ~= "    mov     rsi, r9\n";
        str ~= "    mov     rdx, " ~ leftType.size
                                             .to!string
                                   ~ "\n";
        // String special case
        if (leftType.tag == TypeEnum.CHAR)
        {
            str ~= "    mov     rcx, 1\n";
        }
        // Array case
        else
        {
            str ~= "    mov     rcx, 0\n";
        }
        str ~= "    call    __elem_elem_append\n";
        str ~= "    mov     r8, rax\n";
    }
    else if (leftType.tag == TypeEnum.STRING)
    {
        str ~= "    mov     rdi, r8\n";
        str ~= "    mov     rsi, r9\n";
        if (rightType.tag == TypeEnum.STRING)
        {
            str ~= "    mov     rdx, " ~ char.sizeof
                                             .to!string
                                       ~ "\n";
            str ~= "    mov     rcx, 1\n";
            str ~= "    call    __arr_arr_append\n";
        }
        else if (rightType.tag == TypeEnum.CHAR)
        {
            str ~= "    mov     rdx, " ~ char.sizeof
                                             .to!string
                                       ~ "\n";
            str ~= "    mov     rcx, 1\n";
            str ~= "    call    __arr_elem_append\n";
        }
        // Right type is array of strings, do elem-arr append without string
        // mode enabled
        else
        {
            str ~= "    mov     rdx, " ~ rightType.array
                                                  .arrayType
                                                  .size
                                                  .to!string
                                       ~ "\n";
            str ~= "    mov     rcx, 0\n";
            str ~= "    call    __elem_arr_append\n";
        }
        str ~= "    mov     r8, rax\n";
    }
    // Left type must either be char or array
    else if (rightType.tag == TypeEnum.STRING)
    {
        str ~= "    mov     rdi, r8\n";
        str ~= "    mov     rsi, r9\n";
        if (leftType.tag == TypeEnum.CHAR)
        {
            str ~= "    mov     rdx, " ~ char.sizeof
                                             .to!string
                                       ~ "\n";
            str ~= "    mov     rcx, 1\n";
            str ~= "    call    __elem_arr_append\n";
        }
        // Left type is array of strings, do arr-elem append without string
        // mode enabled
        else
        {
            str ~= "    mov     rdx, " ~ leftType.array
                                                  .arrayType
                                                  .size
                                                  .to!string
                                       ~ "\n";
            str ~= "    mov     rcx, 0\n";
            str ~= "    call    __arr_elem_append\n";
        }
        str ~= "    mov     r8, rax\n";
    }
    else if (leftType.tag == TypeEnum.ARRAY)
    {
        str ~= "    mov     rdi, r8\n";
        str ~= "    mov     rsi, r9\n";
        str ~= "    mov     rdx, " ~ leftType.array
                                             .arrayType
                                             .size
                                             .to!string
                                   ~ "\n";
        str ~= "    mov     rcx, 0\n";
        // Appending two arrays of the same type
        if (leftType.cmp(rightType))
        {
            str ~= "    call    __arr_arr_append\n";
        }
        // Appending an element of the array type (right) to the
        // array (left)
        else if (leftType.array.arrayType.cmp(rightType))
        {
            str ~= "    call    __arr_elem_append\n";
        }
        str ~= "    mov     r8, rax\n";
    }
    // Left type must be elem of right type array
    else if (rightType.tag == TypeEnum.ARRAY)
    {
        str ~= "    mov     rdi, r8\n";
        str ~= "    mov     rsi, r9\n";
        str ~= "    mov     rdx, " ~ leftType.size
                                             .to!string
                                   ~ "\n";
        str ~= "    mov     rcx, 0\n";
        // Appending an element of the array type (left) to the
        // array (right)
        str ~= "    call    __elem_arr_append\n";
        str ~= "    mov     r8, rax\n";
    }
    else
    {
        assert(false, "Unreachable");
    }
    str ~= "    ; append op (~) algorithm end\n";
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
        str ~= compileValueTuple(cast(ValueTupleNode)child, vars);
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
            if ("funcptrsig" in node.data)
            {
                vars.valueTag = "funcptr";
            }
        }
        else if (vars.isFuncName(name))
        {
            vars.valueTag = "func";
            str ~= "    mov    r8, " ~ name ~ "\n";
            // If we are not then immediately invoking this function, then we
            // must be creating a function pointer
            if (node.children.length == 1)
            {
                vars.allocateStackSpace(8);
                auto funcPtrLoc = vars.getTop.to!string;
                scope (exit) vars.deallocateStackSpace(8);
                str ~= "    mov    qword [rbp-" ~ funcPtrLoc ~ "], r8\n";
                str ~= "    mov    rdi, " ~ (REF_COUNT_SIZE
                                           + STRUCT_BUFFER_SIZE
                                           + ENVIRON_PTR_SIZE
                                           + MELLOW_STR_SIZE).to!string
                                          ~ "\n";
                str ~= "    call   malloc\n";
                // Set up memory layout of fat ptr:
                // [8-bytes runtime header,
                //  8 bytes null environ ptr, 8 bytes func ptr]
                str ~= "    mov    dword [rax], 0\n";
                str ~= "    mov    dword [rax+4], 0\n";
                str ~= "    mov    qword [rax+8], 0\n";
                str ~= "    mov    r8, qword [rbp-" ~ funcPtrLoc ~ "]\n";
                str ~= "    mov    qword [rax+16], r8\n";
                str ~= "    mov    r8, rax\n";
            }
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
    auto str = "";
    auto tupleType = node.data["type"].get!(Type*).tuple;
    str ~= "    mov    rdi, " ~ getTupleAllocSize(tupleType).to!string ~ "\n";
    str ~= "    call   malloc\n";
    // Set refcount
    str ~= "    mov    dword [rax], 1\n";
    str ~= "    mov    r8, rax\n";
    vars.allocateStackSpace(8);
    scope (exit) vars.deallocateStackSpace(8);
    auto tupleLoc = vars.getTop.to!string;
    str ~= "    mov    qword [rbp-" ~ tupleLoc ~ "], r8\n";
    foreach (i, child; node.children)
    {
        auto valueOffset = tupleType.getOffsetOfValue(i);
        auto valueType = tupleType.types[i];
        str ~= compileBoolExpr(cast(BoolExprNode)child, vars);
        str ~= "    mov    r10, qword [rbp-" ~ tupleLoc ~ "]\n";
        str ~= "    add    r10, " ~ (REF_COUNT_SIZE
                                   + STRUCT_BUFFER_SIZE
                                   + valueOffset).to!string
                                  ~ "\n";
        str ~= "    mov    " ~ getWordSize(valueType.size)
                             ~ " [r10], r8"
                             ~ getRRegSuffix(valueType.size)
                             ~ "\n";
    }
    str ~= "    mov    r8, qword [rbp-" ~ tupleLoc ~ "]\n";
    return str;
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
    // The 8 is the ref count area and the array length area, each 4 bytes
    auto totalAllocSize = numElems * elemSize + 8;
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
    auto strAllocSize = strTrueLength + REF_COUNT_SIZE
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
    vars.runtimeExterns["__arr_slice"] = true;
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
        str ~= "    mov    rdi, qword [rbp-" ~ valLoc ~ "]\n";
        str ~= "    mov    rsi, r8\n";
        str ~= "    mov    rdx, r9\n";
        str ~= "    mov    rcx, " ~ resultType.size
                                              .to!string
                                  ~ "\n";
        if (resultType.tag == TypeEnum.CHAR)
        {
            str ~= "    mov    r8, 1\n";
        }
        else
        {
            str ~= "    mov    r8, 0\n";
        }
        str ~= "    call    __arr_slice\n";
        str ~= "    mov     r8, rax\n";
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
        auto isExtern = funcSig.isExtern;
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
        // TODO: We need to update this to include passing any stack arguments
        //
        // If the function was declared extern, we have to assume it is a C
        // function which will not yield, or do any other stack switching, but
        // may have an arbitrarily deep call stack without doing any of the
        // stack maintenance that normal mellow functions do. So switch out the
        // underlying stack for the main OS stack, which grows for us
        if (isExtern)
        {
            vars.runtimeExterns["__mellow_use_main_stack"] = true;
            // Call the wrapper function with the function to wrap as the only
            // argument.
            //
            // NOTE: We are "passing" in the wrapped function in r10
            str ~= "    call   __mellow_use_main_stack\n";
        }
        // Otherwise, it is a normal mellow function, so call directly
        else
        {
            str ~= "    call   r10\n";
        }
        str ~= "    mov    r8, rax\n";
        break;
    case "funcptr":
        auto funcSig = node.data["funcsig"].get!(FuncSig*);
        vars.allocateStackSpace(8);
        auto funcPtrLoc = vars.getTop.to!string;
        str ~= "    mov    qword [rbp-" ~ funcPtrLoc ~ "], r8\n";
        // Set r8 to the value of the environment pointer for the func ptr.
        // If the ptr is valid and not null, it will be passed as the first arg
        // to the function, otherwise it isn't passed, in compileArgList
        // TODO; We don't actually correctly pass the environ ptr yet.
        str ~= "    mov    r8, qword [r8+8]\n";
        str ~= compileArgList(cast(FuncCallArgListNode)node.children[0], vars);
        str ~= "    mov    r10, qword [rbp-" ~ funcPtrLoc ~ "]\n";
        // Grab the actual function pointer out of the fat ptr
        str ~= "    mov    r10, qword [r10+16]\n";
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
