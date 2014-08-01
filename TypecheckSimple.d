import std.stdio;
import std.variant;
import std.algorithm;
import std.conv;
import std.range;
import std.array;
import parser;
import visitor;
import typeInfo;
import SymTab;

enum newSymTab = `curSymTab = new SymTab();
                  node.data["symtab"] = curSymTab;`;

enum passthroughSymtab = `node.data["symtab"] = curSymTab;`;

enum childSymTab = `auto tmpSymTab = new SymTab();
                    auto retSymTab = curSymTab;
                    tmpSymTab.parent = curSymTab;
                    curSymTab.children ~= tmpSymTab;
                    curSymTab = tmpSymTab;
                    node.data["symtab"] = curSymTab;
                    scope (exit) curSymTab = retSymTab;`;

enum visitAllChildren = `foreach (child; node.children)
                         {
                             child.accept(this);
                         }`;

enum boolExprBoiler = `if (node.children.length == 1)
                       {
                           mixin(visitNode(0));
                           mixin(adoptChildType(0));
                       }
                       else
                       {
                           mixin(visitAllChildren);
                           foreach (child; node.children)
                           {
                               // TODO: Need to do a check here to verify
                               // boolean type
                           }
                           node.data["type"] = new Prim_Bool();
                       }`;

string adoptChildType(uint index)
{
    return `node.data["type"] =
                node.children[` ~ index.to!string ~ `].data["type"];`;
}

string populateId(uint index)
{
    return `node.children[` ~ index.to!string ~ `].accept(this);`;
}

string grabToken(ASTNode node, uint index)
{
    auto nonTerminal = cast(ASTNonTerminal)node;
    return (cast(ASTTerminal)(nonTerminal.children[index])).token;
}

// TODO: Might be broken
string grabToken(ASTNode node, uint[] indices)
{
    if (indices.length == 1)
    {
        return node.grabToken(indices[0]);
    }
    auto nonTerminal = cast(ASTNonTerminal)node;
    auto child = cast(ASTNonTerminal)(nonTerminal.children[indices[0]]);
    foreach (i; indices[1..$-1])
    {
        child = cast(ASTNonTerminal)(child.children[i]);
    }
    return (cast(ASTTerminal)(child.children[indices[$-1]])).token;
}

string typeAssert(uint index, string type)
{
    return
        `if (node.children[` ~ index.to!string ~ `].data["type"].toString() !=
            "` ~ type ~ `")
            {
                throw new Exception("Expected ` ~ type ~ `" ~
                    "but got " ~ typeid(
                        node.children[` ~ index.to!string ~ `].data["type"]
                                       ).toString() ~ "!");
            }
        `;
}

string visitNode(uint index)
{
    return `node.children[` ~ index.to!string ~ `].accept(this);`;
}

//// Inclusive, exclusive
//string visitRange(uint start, uint finish)
//{
//    return `foreach (child;
//                node.children[` ~ start.to!string ~`..`~ finish.to!string ~ `])
//            {
//                child.accept(this);
//            }`;
//}

string visitSparse(uint[] indices)
{
    auto str = ``;
    foreach (i; indices)
    {
        str ~= visitNode(i);
    }
    return str;
}

bool isIntegralType(Type type)
{
    if (   typeid(type) == typeid(Prim_Long)
        || typeid(type) == typeid(Prim_Ulong)
        || typeid(type) == typeid(Prim_Int)
        || typeid(type) == typeid(Prim_Uint)
        || typeid(type) == typeid(Prim_Short)
        || typeid(type) == typeid(Prim_Ushort)
        || typeid(type) == typeid(Prim_Byte)
        || typeid(type) == typeid(Prim_Ubyte))
    {
        return true;
    }
    return false;
}

class FuncSig
{}

string tracer(string nodeType)
{
    return
    `
    writeln(traceIndent, "Entered: ` ~ nodeType ~ `");
    traceIndent ~= "  ";
    scope(success)
    {
        traceIndent = traceIndent[0..$-2];
        writeln(traceIndent, "Exiting: ` ~ nodeType ~ `");
    }
    `;
}

class TypecheckSimple : Visitor
{
    string traceIndent;
    string curId;
    SymTab curSymTab;
    FuncSig curFunc;

    void visit(ProgramNode node)
    {
        mixin(tracer("ProgramNode"));
        mixin(newSymTab);
        mixin(visitAllChildren);
    }

    void visit(IdentifierNode node)
    {
        mixin(tracer("IdentifierNode"));
        curId = (cast(ASTTerminal)node.children[0]).token;
    }

    void visit(FuncDefNode node)
    {
        mixin(tracer("FuncDefNode"));
        mixin(passthroughSymtab);
        foreach (child; node.children)
        {
            child.accept(this);
        }
    }

    void visit(FuncSignatureNode node)
    {
        mixin(tracer("FuncSignatureNode"));
        mixin(passthroughSymtab);
        mixin(populateId(0));
        curSymTab.syms[curId] = new Symbol(curId, Variant(new FuncSig()));
        mixin(visitSparse( [1, 2, 3] ));
    }

    void visit(FuncBodyBlocksNode node)
    {
        mixin(tracer("FuncBodyBlocksNode"));
        mixin(passthroughSymtab);
        mixin(visitAllChildren);
    }

    void visit(BareBlockNode node)
    {
        mixin(tracer("BareBlockNode"));
        mixin(childSymTab);
        mixin(visitAllChildren);
    }

    void visit(StatementNode node)
    {
        mixin(passthroughSymtab);
        mixin(visitNode(0));
    }

    void visit(ReturnStmtNode node)
    {
        mixin(tracer("ReturnStmtNode"));
        mixin(passthroughSymtab);
        mixin(visitNode(0));
    }

    void visit(BoolExprNode node)
    {
        mixin(tracer("BoolExprNode"));
        mixin(passthroughSymtab);
        mixin(visitNode(0));
        mixin(adoptChildType(0));
    }

    void visit(OrTestNode node)
    {
        mixin(tracer("OrTestNode"));
        mixin(passthroughSymtab);
        mixin(boolExprBoiler);
    }

    void visit(AndTestNode node)
    {
        mixin(tracer("AndTestNode"));
        mixin(passthroughSymtab);
        mixin(boolExprBoiler);
    }

    void visit(NotTestNode node)
    {
        mixin(tracer("NotTestNode"));
        mixin(passthroughSymtab);
        if (typeid(node.children[0]) == typeid(NotTestNode))
        {
            mixin(visitNode(0));
            // TODO: Need to do a check here to verify boolean type of child
            node.data["type"] = new Prim_Bool();
        }
        else
        {
            mixin(visitNode(0));
            mixin(adoptChildType(0));
        }
    }

    void visit(ComparisonNode node)
    {
        mixin(tracer("ComparisonNode"));
        mixin(passthroughSymtab);
        if (node.children.length == 1)
        {
            mixin(visitNode(0));
            mixin(adoptChildType(0));
        }
        else
        {
            // TODO: Need to do checks in here to verify comparable type, based
            // on comparison operator
            mixin(visitNode(0));
            for (auto i = 2; i < node.children.length; i += 2)
            {
                node.children[i].accept(this);
                // comp is the comparison token used
                auto comp = node.grabToken(i-1);
            }
            node.data["type"] = new Prim_Bool();
        }
    }

    void visit(ExprNode node)
    {
        mixin(tracer("ExprNode"));
        mixin(passthroughSymtab);
        mixin(visitNode(0));
        mixin(adoptChildType(0));
    }

    void visit(OrExprNode node)
    {
        mixin(tracer("OrExprNode"));
        mixin(passthroughSymtab);
        mixin(visitNode(0));
        mixin(adoptChildType(0));
    }

    void visit(XorExprNode node)
    {
        mixin(tracer("XorExprNode"));
        mixin(passthroughSymtab);
        mixin(visitNode(0));
        mixin(adoptChildType(0));
    }

    void visit(AndExprNode node)
    {
        mixin(tracer("AndExprNode"));
        mixin(passthroughSymtab);
        mixin(visitNode(0));
        mixin(adoptChildType(0));
    }

    void visit(ShiftExprNode node)
    {
        mixin(tracer("ShiftExprNode"));
        mixin(passthroughSymtab);
        mixin(visitNode(0));
        mixin(adoptChildType(0));
    }

    void visit(SumExprNode node)
    {
        mixin(tracer("SumExprNode"));
        mixin(passthroughSymtab);
        mixin(visitNode(0));
        mixin(adoptChildType(0));
    }

    void visit(ProductExprNode node)
    {
        mixin(tracer("ProductExprNode"));
        mixin(passthroughSymtab);
        mixin(visitNode(0));
        mixin(adoptChildType(0));
    }

    void visit(ValueNode node)
    {
        mixin(tracer("ValueNode"));
        mixin(passthroughSymtab);
        mixin(visitNode(0));
        mixin(adoptChildType(0));
    }

    void visit(NumberNode node)
    {
        mixin(tracer("NumberNode"));
        mixin(passthroughSymtab);
        mixin(visitNode(0));
        mixin(adoptChildType(0));
    }

    void visit(IntNumNode node)
    {
        mixin(tracer("IntNumNode"));
        mixin(passthroughSymtab);
        node.data["type"] = new Prim_Int();
    }

    void visit(FloatNumNode node)
    {
        mixin(tracer("FloatNumNode"));
        mixin(passthroughSymtab);
        node.data["type"] = new Prim_Double();
    }

    void visit(CharLitNode node)
    {
        mixin(tracer("CharLitNode"));
        mixin(passthroughSymtab);
        node.data["type"] = new Prim_Char();
    }

    void visit(StringLitNode node)
    {
        mixin(tracer("StringLitNode"));
        mixin(passthroughSymtab);
        node.data["type"] = new Prim_String();
    }

    void visit(VariableNode node)
    {
        mixin(tracer("VariableNode"));
        mixin(passthroughSymtab);
        mixin(populateId(0));
        // Try to locate the variable in the symbol table, and set the type of
        // this node to the type of the variable if it exists
        if (curId in curSymTab.syms)
        {
            node.data["type"] = curSymTab.syms[curId].type;
        }
        else
        {
            auto searchSymTab = curSymTab.parent;
            while (searchSymTab !is null)
            {
                if (curId in searchSymTab.syms)
                {
                    node.data["type"] = searchSymTab.syms[curId].type;
                    break;
                }
                searchSymTab = searchSymTab.parent;
            }
        }
        if ("type" !in node.data)
        {
            throw new Exception("Could not find variable [" ~ curId ~ "]!");
        }
    }

    void visit(DeclarationNode node)
    {
        mixin(tracer("DeclarationNode"));
        mixin(passthroughSymtab);
        mixin(visitNode(0));
    }

    void visit(DeclTypeInferNode node)
    {
        mixin(tracer("DeclTypeInferNode"));
        mixin(passthroughSymtab);
        if (typeid(node.children[0]) == typeid(IdTupleNode))
        {

        }
        // IdentifierNode
        else
        {
            mixin(populateId(0));
            mixin(visitNode(1));
            auto type = node.children[1].data["type"];
            auto searchSymTab = curSymTab;
            while (searchSymTab !is null)
            {
                if (curId in searchSymTab.syms)
                {
                    throw new Exception(
                        curId ~ " already exists in symbol table!");
                }
                searchSymTab = searchSymTab.parent;
            }
            curSymTab.syms[curId] = new Symbol(curId, type);
        }
    }



    void visit(CharRangeNode node) {}
    void visit(IntRangeNode node) {}
    void visit(ExprCastNode node) {}
    void visit(ParenExprNode node) {}
    void visit(ArrayLiteralNode node) {}
    void visit(LambdaNode node) {}
    void visit(LambdaArgsNode node) {}
    void visit(BooleanLiteralNode node) {}
    void visit(CompOpNode node) {}
    void visit(SumOpNode node) {}
    void visit(FuncDefArgListNode node) {}
    void visit(FuncSigArgNode node) {}
    void visit(SpNode node) {}
    void visit(StructDefNode node) {}
    void visit(StructBodyNode node) {}
    void visit(StructEntryNode node) {}
    void visit(StructFunctionNode node) {}
    void visit(FuncReturnTypeNode node) {}
    void visit(InBlockNode node) {}
    void visit(OutBlockNode node) {}
    void visit(ReturnModBlockNode node) {}
    void visit(BodyBlockNode node) {}
    void visit(StorageClassNode node) {}
    void visit(RefClassNode node) {}
    void visit(ConstClassNode node) {}
    void visit(VariantDefNode node) {}
    void visit(VariantBodyNode node) {}
    void visit(VariantEntryNode node) {}
    void visit(VariantVarDeclListNode node) {}
    void visit(VariantSubTypeNode node) {}
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
    void visit(DeclAssignmentNode node) {}
    void visit(AssignExistingNode node) {}
    void visit(AssignExistingOpNode node) {}
    void visit(AssignmentNode node) {}
    void visit(CondAssignmentsNode node) {}
    void visit(CondAssignNode node) {}
    void visit(SliceLengthSentinelNode node) {}
    void visit(ChanReadNode node) {}
    void visit(AtomNode node) {}
    void visit(TrailerNode node) {}
    void visit(DynArrAccessNode node) {}
    void visit(TemplateInstanceMaybeTrailerNode node) {}
    void visit(FuncCallTrailerNode node) {}
    void visit(MemberAccessNode node) {}
    void visit(SlicingNode node) {}
    void visit(SingleIndexNode node) {}
    void visit(IndexRangeNode node) {}
    void visit(StartToIndexRangeNode node) {}
    void visit(IndexToEndRangeNode node) {}
    void visit(IndexToIndexRangeNode node) {}
    void visit(FuncCallArgListNode node) {}
    void visit(DotAccessNode node) {}
    void visit(MatchStmtNode node) {}
    void visit(MatchExprNode node) {}
    void visit(MatchWhenNode node) {}
    void visit(MatchWhenExprNode node) {}
    void visit(MatchDefaultNode node) {}
    void visit(VariableTypePairNode node) {}
    void visit(VariableTypePairTupleNode node) {}
    void visit(IdTupleNode node) {}
    void visit(VariantIdTupleNode node) {}
    void visit(TypeIdNode node) {}
    void visit(ChanTypeNode node) {}
    void visit(ArrayTypeNode node) {}
    void visit(PointerDeclNode node) {}
    void visit(DynArrayDeclNode node) {}
    void visit(SetTypeNode node) {}
    void visit(HashTypeNode node) {}
    void visit(TypeTupleNode node) {}
    void visit(UserTypeNode node) {}
    void visit(BasicTypeNode node) {}
    void visit(TemplateInstantiationNode node) {}
    void visit(TemplateParamNode node) {}
    void visit(TemplateParamListNode node) {}
    void visit(TemplateAliasNode node) {}
    void visit(TemplateTypeParamsNode node) {}
    void visit(TemplateTypeParamListNode node) {}
    void visit(ASTTerminal node) {}

    void dumpSymTab()
    {
        curSymTab.getTopLevel.dump();
    }
}

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
        auto printVisitor = new PrintVisitor();
        printVisitor.visit(cast(ProgramNode)topNode);
        auto vis = new TypecheckSimple();
        vis.visit(cast(ProgramNode)topNode);
        printVisitor.visit(cast(ProgramNode)topNode);
        vis.dumpSymTab();
    }
    else
    {
        writeln("Failed to parse!");
    }
    return 0;
}
