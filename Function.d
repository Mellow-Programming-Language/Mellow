import std.stdio;
import std.variant;
import std.algorithm;
import std.conv;
import std.range;
import std.array;
import parser;
import visitor;
import SymTab;
import ASTUtils;
import typedecl;
import Record;

// CLosures and struct member functions can be implemented in exactly the same
// way. The 'this' pointer and the environment pointer for closures are
// identical, as long as the pointer points to a block of memory where each
// variable is allocated. That is, a struct reference pointer is simply a
// pointer to memory where each member is allocated sequentially. If the
// environment pointer follows the same pattern, then the implementation for
// each is the same, and perhaps building the datastructures for handling them
// in the compiler can be the same as well

struct VarTypePair
{
    string varName;
    Type* type;
    bool closedOver;

    auto format()
    {
        return varName ~ ": " ~ type.format();
    }
}

// The 'header' for a function type. Note that a function can be any of the
// three of being a closure, a struct member function, or neither. A function
// cannot both be a closure and a struct member function, so there will only
// ever be, at most, a single 'implicit' leading argument, whether it be
// an environment-pointer or a 'this' pointer
struct FuncSig
{
    // The actual name of the function; that which can be called
    string funcName;
    // A possibly zero-length list of variables that are closed over, indicating
    // this is a closure function. If the length is zero, the number of
    // arguments to the actual implementation of the function is the number
    // of arguments in 'funcArgs', otherwise there is an additional
    // environment-pointer argument
    VarTypePair*[] closureVars;
    // A possibly-empty string indicating the struct that this function is a
    // member of. If this string is empty, then the number of arguments to the
    // actual implementation of this function is the number of arguments in
    // 'funcArgs', otherwise there is an additional 'this' pointer
    string memberOf;
    // The types of the arguments to the function, in the order they appeared
    // in the original argument list
    VarTypePair*[] funcArgs;
    // The return type. Since it's a bare type, it can possibly be a tuple of
    // types
    Type* returnType;
}

struct SymbolScope
{
    VarTypePair*[string] decls;

    auto format()
    {
        return decls.values.map!(a => a.format).join(", ");
    }
}

auto format(SymbolScope[] symbols)
{
    string str = "";
    string indent = "";
    foreach (symbolScope; symbols)
    {
        str ~= indent ~ symbolScope.format ~ "\n";
        indent ~= "  ";
    }
    return str;
}

struct FunctionScope
{
    SymbolScope[] syms;
}

struct ScopeLookupResult
{
    ulong funcIndex;
    ulong symIndex;
    bool nonlocal;
    bool success;

    this (ulong funcIndex, ulong symIndex, bool nonlocal, bool success)
    {
        this.funcIndex = funcIndex;
        this.symIndex = symIndex;
        this.nonlocal = nonlocal;
        this.success = success;
    }
}

auto scopeLookup(FunctionScope[] funcScopes, string id)
{
    bool nonlocal = false;
    foreach_reverse (i, funcScope; funcScopes)
    {
        foreach_reverse (j, symScope; funcScope.syms)
        {
            if (id in symScope.decls)
            {
                if (i < funcScopes.length - 1)
                {
                    nonlocal = true;
                }
                return new ScopeLookupResult(i, j, nonlocal, true);
            }
        }
    }
    return new ScopeLookupResult(0, 0, false, false);
}

void updateIfClosedOver(FunctionScope[] funcScopes, string id)
{
    auto lookup = funcScopes.scopeLookup(id);
    if (lookup.success && lookup.nonlocal)
    {
        funcScopes[lookup.funcIndex].syms[lookup.symIndex]
                                    .decls[id]
                                    .closedOver = true;
    }
}

Type* instantiateAggregate(RecordBuilder records, AggregateType* aggregate)
{
    if (aggregate.typeName in records.structDefs)
    {
        auto structDef = records.structDefs[aggregate.typeName].copy;
        Type*[string] mappings;
        if (aggregate.templateInstantiations.length
            != structDef.templateParams.length)
        {
            throw new Exception("Template instantiation count mismatch.");
        }
        else
        {
            foreach (var, type; lockstep(structDef.templateParams,
                                    aggregate.templateInstantiations))
            {
                mappings[var] = type.copy;
            }
        }
        structDef.instantiate(mappings);
        auto type = new Type();
        type.tag = TypeEnum.STRUCT;
        type.structDef = structDef;
        return type;
    }
    else if (aggregate.typeName in records.variantDefs)
    {
        auto variantDef = records.variantDefs[aggregate.typeName].copy;
        Type*[string] mappings;
        if (aggregate.templateInstantiations.length
            != variantDef.templateParams.length)
        {
            throw new Exception("Template instantiation count mismatch.");
        }
        else
        {
            foreach (var, type; lockstep(variantDef.templateParams,
                                    aggregate.templateInstantiations))
            {
                mappings[var] = type.copy;
            }
        }
        variantDef.instantiate(mappings);
        auto type = new Type();
        type.tag = TypeEnum.VARIANT;
        type.variantDef = variantDef;
        return type;
    }
    else
    {
        throw new Exception("Instantiation of non-existent type.");
    }
}

debug (TYPECHECK)
void dumpDecls(VarTypePair*[] decls)
{
    foreach (decl; decls)
    {
        decl.format.writeln;
    }
}

class FunctionBuilder : Visitor
{
    RecordBuilder records;
    string id;
    string[] idTuple;
    string funcName;
    string[] templateParams;
    VarTypePair*[] funcArgs;
    FuncSig[] toplevelFuncs;
    Type* returnType;
    // The higher the index, the deeper the scope
    FunctionScope[] funcScopes;
    VarTypePair*[] decls;
    Type* lvalue;

    mixin TypeVisitors;

    this (ProgramNode node, RecordBuilder records)
    {
        this.records = records;
        builderStack.length++;
        // Just do function definitions
        auto funcDefs = node.children
                            .filter!(a => typeid(a) == typeid(FuncDefNode));
        foreach (funcDef; funcDefs)
        {
            funcDef.accept(this);
        }
    }

    private auto collectMultiples(T)(T[] elems)
    {
        bool[T] found;
        bool[T] multiples;
        foreach (elem; elems)
        {
            if (elem in found)
            {
                multiples[elem] = true;
            }
            found[elem] = true;
        }
        return multiples.keys;
    }

    void visit(FuncDefNode node)
    {
        funcScopes.length++;
        funcScopes[$-1].syms.length++;
        // Visit FuncSignatureNode
        node.children[0].accept(this);
        FuncSig funcSig;
        funcSig.funcName = funcName;
        funcSig.funcArgs = funcArgs;
        funcSig.returnType = returnType;
        // Visit FuncBodyBlocksNode
        node.children[1].accept(this);

        // Do final put-together here

        funcScopes.length--;
    }

    void visit(FuncSignatureNode node)
    {
        // Visit IdentifierNode, populate 'id'
        node.children[0].accept(this);
        funcName = id;
        writeln("FuncName: ", id);
        // Visit TemplateTypeParamsNode
        node.children[1].accept(this);
        // Visit FuncDefArgListNode
        node.children[2].accept(this);
        // Visit FuncReturnTypeNode
        node.children[3].accept(this);
    }

    void visit(IdentifierNode node)
    {
        id = (cast(ASTTerminal)node.children[0]).token;
    }

    void visit(IdTupleNode node)
    {
        idTuple = [];
        foreach (child; node.children)
        {
            child.accept(this);
            idTuple ~= id;
        }
    }

    void visit(FuncDefArgListNode node)
    {
        foreach (child; node.children)
        {
            // Visit FuncSigArgNode
            child.accept(this);
        }
    }

    void visit(FuncSigArgNode node)
    {
        // Visit IdentifierNode, populate 'id'
        node.children[0].accept(this);
        string argName = id;
        // Visit TypeIdNode. Note going out of order here
        node.children[$-1].accept(this);
        auto argType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        argType.refType = false;
        argType.constType = false;
        if (node.children.length > 2)
        {
            // Visit StorageClassNode
            foreach (storageClass; node.children[1..$-1])
            {
                if (typeid(storageClass) == typeid(RefClassNode))
                {
                    argType.refType = true;
                }
                else if (typeid(storageClass) == typeid(ConstClassNode))
                {
                    argType.constType = true;
                }
            }
        }
        auto pair = new VarTypePair();
        pair.varName = argName;
        pair.type = argType;
        funcArgs ~= pair;
        funcScopes[$-1].syms[$-1].decls[argName] = pair;
        writeln(format(funcScopes[$-1].syms));
    }

    void visit(FuncReturnTypeNode node)
    {
        if (node.children.length > 0)
        {
            node.children[0].accept(this);
            returnType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
        }
    }

    void visit(FuncBodyBlocksNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(BareBlockNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(StatementNode node)
    {
        node.children[0].accept(this);
    }

    void visit(ReturnStmtNode node)
    {
        if (node.children.length > 0)
        {
            node.children[0].accept(this);
        }
    }

    void visit(BoolExprNode node)
    {
        node.children[0].accept(this);
    }

    void visit(OrTestNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!resultType.tag != TypeEnum.BOOL
                || !nextType.tag != TypeEnum.BOOL)
            {
                throw new Exception("Non-bool type in LOGIC-OR.");
            }
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(AndTestNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!resultType.tag != TypeEnum.BOOL
                || !nextType.tag != TypeEnum.BOOL)
            {
                throw new Exception("Non-bool type in LOGIC-AND.");
            }
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(NotTestNode node)
    {
        node.children[0].accept(this);
        if (typeid(node.children[0]) == typeid(NotTestNode))
        {
            if (builderStack[$-1][$-1].tag != TypeEnum.BOOL)
            {
                throw new Exception("Cannot negate non-bool type.");
            }
        }
    }

    void visit(ComparisonNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        Type* chainCompare = null;
        if (node.children.length > 1)
        {
            auto op = (cast(ASTTerminal)node.children[1]).token;
            node.children[2].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            final switch (op)
            {
            case "<=":
            case ">=":
            case "<":
            case ">":
                if (!resultType.isNumeric || !nextType.isNumeric)
                {
                    throw new Exception("Cannot compare non-integral types.");
                }
                break;
            case "==":
            case "!=":
                if (resultType.isNumeric && nextType.isNumeric) {}
                else if (resultType.cmp(nextType) &&
                      (resultType.tag == TypeEnum.CHAR
                    || resultType.tag == TypeEnum.BOOL
                    || resultType.tag == TypeEnum.STRING)) {}
                else
                {
                    throw new Exception("Mismatched types for equality cmp.");
                }
                break;
            case "<in>":
                if (resultType.tag != TypeEnum.SET
                    || nextType.tag != TypeEnum.SET
                    || !resultType.set.setType.cmp(nextType.set.setType))
                {
                    throw new Exception("Mismatched types in <in> op.");
                }
                break;
            case "in":
                if (nextType.tag != TypeEnum.SET
                    || !nextType.set.setType.cmp(resultType))
                {
                    throw new Exception("Mismatched types in in op.");
                }
                break;
            }
            auto boolType = new Type();
            boolType.tag = TypeEnum.BOOL;
            resultType = boolType;
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(ExprNode node)
    {
        node.children[0].accept(this);
    }

    void visit(OrExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!resultType.isIntegral || !nextType.isIntegral)
            {
                throw new Exception("Non-integral type in BIT-OR operation.");
            }
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(XorExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!resultType.isIntegral || !nextType.isIntegral)
            {
                throw new Exception("Non-integral type in BIT-XOR operation.");
            }
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(AndExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!resultType.isIntegral || !nextType.isIntegral)
            {
                throw new Exception("Non-integral type in BIT-AND operation.");
            }
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(ShiftExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!resultType.isIntegral || !nextType.isIntegral)
            {
                throw new Exception("Non-integral type in shift operation.");
            }
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(SumExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            auto op = (cast(ASTTerminal)node.children[i-1]).token;
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            final switch (op)
            {
            case "+":
            case "-":
                resultType = promoteNumeric(resultType, nextType);
                break;
            case "<|>":
            case "<&>":
            case "<^>":
            case "<->":
                if (!resultType.cmp(nextType)
                    || resultType.tag != TypeEnum.SET
                    || nextType.tag != TypeEnum.SET)
                {
                    throw new Exception("Type mismatch in set operation.");
                }
                break;
            case "~":
                throw new Exception("UNIMPLEMENTED SumExprNode");
            }
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(ProductExprNode node)
    {
        node.children[0].accept(this);
        auto resultType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        for (auto i = 2; i < node.children.length; i += 2)
        {
            auto op = (cast(ASTTerminal)node.children[i-1]).token;
            node.children[i].accept(this);
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!resultType.isNumeric || !nextType.isNumeric)
            {
                throw new Exception("Cannot perform " ~ op ~ " on non-arith.");
            }
            if (op == "%" && (resultType.isFloat || nextType.isFloat))
            {
                throw new Exception("% (modulus) undefined for float types.");
            }
            resultType = promoteNumeric(resultType, nextType);
        }
        builderStack[$-1] ~= resultType;
    }

    void visit(ValueNode node)
    {
        if (typeid(node.children[0]) == typeid(IdentifierNode))
        {
            node.children[0].accept(this);
            auto varName = id;
            auto lookup = funcScopes.scopeLookup(varName);
            if (!lookup.success)
            {
                throw new Exception("No variable [" ~ varName ~ "].");
            }
            auto varType = funcScopes[lookup.funcIndex].syms[lookup.symIndex]
                                                       .decls[varName]
                                                       .type;
            builderStack[$-1] ~= varType;
        }
        else
        {
            foreach (child; node.children)
            {
                child.accept(this);
            }
        }
    }

    void visit(ParenExprNode node)
    {
        node.children[0].accept(this);
    }

    void visit(NumberNode node)
    {
        node.children[0].accept(this);
    }

    void visit(IntNumNode node)
    {
        auto valType = new Type();
        valType.tag = TypeEnum.INT;
        builderStack[$-1] ~= valType;
    }

    void visit(FloatNumNode node)
    {
        auto valType = new Type();
        valType.tag = TypeEnum.FLOAT;
        builderStack[$-1] ~= valType;
    }

    void visit(CharLitNode node)
    {
        auto valType = new Type();
        valType.tag = TypeEnum.CHAR;
        builderStack[$-1] ~= valType;
    }

    void visit(StringLitNode node)
    {
        auto valType = new Type();
        valType.tag = TypeEnum.STRING;
        builderStack[$-1] ~= valType;
    }

    void visit(BooleanLiteralNode node)
    {
        auto valType = new Type();
        valType.tag = TypeEnum.BOOL;
        builderStack[$-1] ~= valType;
    }

    void visit(ArrayLiteralNode node)
    {
        node.children[0].accept(this);
        auto valType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        foreach (child; node.children[1..$])
        {
            auto nextType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (!valType.cmp(nextType))
            {
                throw new Exception("Non-uniform type in array literal");
            }
        }
        auto arrayType = new ArrayType();
        arrayType.arrayType = valType;
        auto type = new Type();
        type.tag = TypeEnum.ARRAY;
        type.array = arrayType;
        builderStack[$-1] ~= type;
    }

    void visit(VariableTypePairNode node)
    {
        // Visit IdentifierNode, populate 'id'
        node.children[0].accept(this);
        auto varName = id;
        // Visit TypeIdNode
        node.children[1].accept(this);
        auto varType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        auto pair = new VarTypePair();
        pair.varName = varName;
        pair.type = varType;
        funcScopes[$-1].syms[$-1].decls[varName] = pair;
        decls ~= pair;
    }

    void visit(VariableTypePairTupleNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(DeclarationNode node)
    {
        node.children[0].accept(this);
        debug (TYPECHECK) decls.dumpDecls;
        decls = [];
    }

    void visit(DeclAssignmentNode node)
    {
        node.children[0].accept(this);
        node.children[1].accept(this);
        auto varType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (varType.tag == TypeEnum.TUPLE)
        {
            auto tupleTypes = varType.tuple.types;
            if (tupleTypes.length != decls.length)
            {
                throw new Exception("Tuple member count mismatch.");
            }
            foreach (decl, varType; lockstep(decls, tupleTypes))
            {
                if (!decl.type.cmp(varType))
                {
                    throw new Exception("Type mismatch in tuple unpack.");
                }
            }
        }
        else
        {
            if (!decls[$-1].type.cmp(varType))
            {
                writeln(decls[$-1].type.format);
                writeln("vs.");
                writeln(varType.format);
                throw new Exception("Type mismatch in decl assignment.");
            }
        }
    }

    void visit(AssignExistingNode node)
    {
        lvalue = null;
        node.children[0].accept(this);
        auto left = lvalue;
        lvalue = null;
        node.children[2].accept(this);
        auto varType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (!left.cmp(varType))
        {
            throw new Exception("Type mismatch in assign-existing.");
        }
    }

    void visit(DeclTypeInferNode node)
    {
        node.children[0].accept(this);
        if (typeid(node.children[0]) == typeid(IdTupleNode))
        {
            string[] varNames = idTuple;
            node.children[1].accept(this);
            auto varTuple = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (varTuple.tag != TypeEnum.TUPLE)
            {
                throw new Exception("Non-Tuple type!");
            }
            auto tupleTypes = varTuple.tuple.types;
            if (tupleTypes.length != varNames.length)
            {
                throw new Exception("Tuple member count mismatch.");
            }
            foreach (varName, varType; lockstep(varNames, tupleTypes))
            {
                auto pair = new VarTypePair();
                pair.varName = varName;
                pair.type = varType;
                funcScopes[$-1].syms[$-1].decls[varName] = pair;
            }
        }
        else if (typeid(node.children[0]) == typeid(IdentifierNode))
        {
            string varName = id;
            node.children[1].accept(this);
            auto varType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            auto pair = new VarTypePair();
            pair.varName = varName;
            pair.type = varType;
            funcScopes[$-1].syms[$-1].decls[varName] = pair;
        }
        writeln(format(funcScopes[$-1].syms));
    }

    void visit(AssignmentNode node)
    {
        node.children[0].accept(this);
    }

    void visit(ValueTupleNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(LorRValueNode node)
    {
        node.children[0].accept(this);
        string varName = id;
        if (lvalue is null)
        {
            funcScopes.updateIfClosedOver(varName);
            auto lookup = funcScopes.scopeLookup(varName);
            if (!lookup.success)
            {
                throw new Exception("Cannot assign to undeclared variable.");
            }
            auto varType = funcScopes[lookup.funcIndex].syms[lookup.symIndex]
                                                       .decls[varName]
                                                       .type;
            lvalue = varType.copy;
        }
        // This means the varName is a member of whatever the current lvalue
        // type is
        else
        {
            switch (lvalue.tag)
            {
            case TypeEnum.STRUCT:
                foreach (member; lvalue.structDef.members)
                {
                    if (member.name == varName)
                    {
                        lvalue = member.type.copy;
                        break;
                    }
                }
                break;
            case TypeEnum.VARIANT:
                foreach (constructor; lvalue.variantDef.members)
                {
                    if (constructor.constructorName == varName)
                    {
                        lvalue = constructor.constructorElems.copy;
                        break;
                    }
                }
                break;
            default:
                throw new Exception("No member of non-struct type.");
            }
        }
        if (node.children.length > 1)
        {
            node.children[1].accept(this);
        }
    }

    void visit(LorRTrailerNode node)
    {
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(LorRMemberAccessNode node)
    {
        node.children[0].accept(this);
    }

    void visit(SlicingNode node)
    {
        // We're working on an lvalue
        if (lvalue !is null)
        {
            if (lvalue.tag != TypeEnum.ARRAY)
            {
                throw new Exception("Cannot slice non-array type.");
            }
            node.children[0].accept(this);
            auto sliceType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            // Single index, so not a slice. Else, we maintain the array
            // type, since we're just slicing, so leave lvalue as is
            if (sliceType.tag != TypeEnum.TUPLE)
            {
                lvalue = lvalue.array.arrayType;
            }
        }
        // We're working on an rvalue
        else
        {
            auto arrayType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            if (arrayType.tag != TypeEnum.ARRAY)
            {
                throw new Exception("Cannot slice non-array type.");
            }
            node.children[0].accept(this);
            auto sliceType = builderStack[$-1][$-1];
            builderStack[$-1] = builderStack[$-1][0..$-1];
            // If it's not a range, then it's a single index, meaning a single
            // instance of what the array type contains
            if (sliceType.tag != TypeEnum.TUPLE)
            {
                builderStack[$-1] ~= arrayType.array.arrayType;
            }
            // Otherwise, it's a range, meaning the outgoing type is just the
            // array type again
            else
            {
                builderStack[$-1] ~= arrayType;
            }
        }
    }

    void visit(SingleIndexNode node)
    {
        node.children[0].accept(this);
        auto indexType = builderStack[$-1][$-1];
        if (!indexType.isIntegral)
        {
            throw new Exception("Index type must be integral.");
        }
    }

    void visit(IndexRangeNode node)
    {
        node.children[0].accept(this);
    }

    void visit(StartToIndexRangeNode node)
    {
        node.children[0].accept(this);
        auto indexType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (!indexType.isIntegral)
        {
            throw new Exception("Index type must be integral.");
        }
        auto indexEnd = new Type();
        indexEnd.tag = TypeEnum.LONG;
        auto range = new TupleType();
        range.types = [indexType] ~ [indexEnd];
        auto wrap = new Type();
        wrap.tag = TypeEnum.TUPLE;
        wrap.tuple = range;
        builderStack[$-1] ~= wrap;
    }

    void visit(IndexToEndRangeNode node)
    {
        node.children[0].accept(this);
        auto indexType = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (!indexType.isIntegral)
        {
            throw new Exception("Index type must be integral.");
        }
        auto indexEnd = new Type();
        indexEnd.tag = TypeEnum.LONG;
        auto range = new TupleType();
        range.types = [indexType] ~ [indexEnd];
        auto wrap = new Type();
        wrap.tag = TypeEnum.TUPLE;
        wrap.tuple = range;
        builderStack[$-1] ~= wrap;
    }

    void visit(IndexToIndexRangeNode node)
    {
        node.children[0].accept(this);
        auto indexStart = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (!indexStart.isIntegral)
        {
            throw new Exception("Index type must be integral.");
        }
        node.children[1].accept(this);
        auto indexEnd = builderStack[$-1][$-1];
        builderStack[$-1] = builderStack[$-1][0..$-1];
        if (!indexEnd.isIntegral)
        {
            throw new Exception("Index type must be integral.");
        }
        auto range = new TupleType();
        range.types = [indexStart] ~ [indexEnd];
        auto wrap = new Type();
        wrap.tag = TypeEnum.TUPLE;
        wrap.tuple = range;
        builderStack[$-1] ~= wrap;
    }

    void visit(UserTypeNode node)
    {
        node.children[0].accept(this);
        string userTypeName = id;
        auto aggregate = new AggregateType();
        aggregate.typeName = userTypeName;
        if (node.children.length > 1)
        {
            builderStack.length++;
            node.children[1].accept(this);
            aggregate.templateInstantiations = builderStack[$-1];
            builderStack.length--;
        }
        builderStack[$-1] ~= instantiateAggregate(records, aggregate);
    }

    void visit(LambdaNode node) {}
    void visit(LambdaArgsNode node) {}
    void visit(StructFunctionNode node) {}
    void visit(InBlockNode node) {}
    void visit(OutBlockNode node) {}
    void visit(ReturnModBlockNode node) {}
    void visit(BodyBlockNode node) {}
    void visit(StorageClassNode node) {}
    void visit(RefClassNode node) {}
    void visit(ConstClassNode node) {}
    void visit(InterfaceDefNode node) {}
    void visit(InterfaceBodyNode node) {}
    void visit(InterfaceEntryNode node) {}
    void visit(IfStmtNode node) {}
    void visit(ElseIfsNode node) {}
    void visit(ElseIfStmtNode node) {}
    void visit(ElseStmtNode node) {}
    void visit(WhileStmtNode node) {}
    void visit(ForStmtNode node) {}
    void visit(ForInitNode node) {}
    void visit(ForConditionalNode node) {}
    void visit(ForPostExpressionNode node) {}
    void visit(ForeachStmtNode node) {}
    void visit(ForeachArgsNode node) {}
    void visit(SpawnStmtNode node) {}
    void visit(YieldStmtNode node) {}
    void visit(ChanWriteNode node) {}
    void visit(FuncCallNode node) {}
    void visit(AssignExistingOpNode node) {}
    void visit(CondAssignmentsNode node) {}
    void visit(CondAssignNode node) {}
    void visit(SliceLengthSentinelNode node) {}
    void visit(ChanReadNode node) {}
    void visit(TrailerNode node) {}
    void visit(DynArrAccessNode node) {}
    void visit(TemplateInstanceMaybeTrailerNode node) {}
    void visit(FuncCallTrailerNode node) {}
    void visit(FuncCallArgListNode node) {}
    void visit(DotAccessNode node) {}
    void visit(MatchStmtNode node) {}
    void visit(MatchExprNode node) {}
    void visit(MatchWhenNode node) {}
    void visit(MatchWhenExprNode node) {}
    void visit(MatchDefaultNode node) {}

    void visit(ASTTerminal node) {}
    void visit(StructDefNode node) {}
    void visit(StructBodyNode node) {}
    void visit(StructEntryNode node) {}
    void visit(VariantDefNode node) {}
    void visit(VariantBodyNode node) {}
    void visit(VariantEntryNode node) {}
    void visit(CharRangeNode node) {}
    void visit(IntRangeNode node) {}
    void visit(CompOpNode node) {}
    void visit(SumOpNode node) {}
    void visit(SpNode node) {}
    void visit(ProgramNode node) {}
}
