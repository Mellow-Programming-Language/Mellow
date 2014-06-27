import std.stdio;
import visitor;
import parser;

class TypecheckPrintVisitor : Visitor
{
    string indent;
    this ()
    {
        indent = "";
    }
    void visit(ProgramNode node)
    {
        write(indent, "PROGRAMNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(SpNode node)
    {
        write(indent, "SPNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(StructDefNode node)
    {
        write(indent, "STRUCTDEFNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(StructBodyNode node)
    {
        write(indent, "STRUCTBODYNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(StructEntryNode node)
    {
        write(indent, "STRUCTENTRYNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(StructFunctionNode node)
    {
        write(indent, "STRUCTFUNCTIONNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(FuncDefNode node)
    {
        write(indent, "FUNCDEFNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(FuncDefArgListNode node)
    {
        write(indent, "FUNCDEFARGLISTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(FuncSigArgNode node)
    {
        write(indent, "FUNCSIGARGNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(FuncReturnTypeNode node)
    {
        write(indent, "FUNCRETURNTYPENODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(FuncBodyBlocksNode node)
    {
        write(indent, "FUNCBODYBLOCKSNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(InBlockNode node)
    {
        write(indent, "INBLOCKNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(OutBlockNode node)
    {
        write(indent, "OUTBLOCKNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ReturnModBlockNode node)
    {
        write(indent, "RETURNMODBLOCKNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(BodyBlockNode node)
    {
        write(indent, "BODYBLOCKNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(BareBlockNode node)
    {
        write(indent, "BAREBLOCKNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(StorageClassNode node)
    {
        write(indent, "STORAGECLASSNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(RefClassNode node)
    {
        write(indent, "REFCLASSNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ConstClassNode node)
    {
        write(indent, "CONSTCLASSNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(VariantNode node)
    {
        write(indent, "VARIANTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(VariantBodyNode node)
    {
        write(indent, "VARIANTBODYNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(VariantEntryNode node)
    {
        write(indent, "VARIANTENTRYNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(VariantVarDeclListNode node)
    {
        write(indent, "VARIANTVARDECLLISTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(StatementNode node)
    {
        write(indent, "STATEMENTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ReturnStmtNode node)
    {
        write(indent, "RETURNSTMTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(IfStmtNode node)
    {
        write(indent, "IFSTMTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ElseIfStmtNode node)
    {
        write(indent, "ELSEIFSTMTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ElseStmtNode node)
    {
        write(indent, "ELSESTMTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(WhileStmtNode node)
    {
        write(indent, "WHILESTMTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ForStmtNode node)
    {
        write(indent, "FORSTMTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ForInitNode node)
    {
        write(indent, "FORINITNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ForeachStmtNode node)
    {
        write(indent, "FOREACHSTMTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(Foreach1Node node)
    {
        write(indent, "FOREACH1NODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(Foreach2Node node)
    {
        write(indent, "FOREACH2NODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(DeclAssignmentNode node)
    {
        write(indent, "DECLASSIGNMENTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(DeclTypeInferNode node)
    {
        write(indent, "DECLTYPEINFERNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(AssignmentStmtNode node)
    {
        write(indent, "ASSIGNMENTSTMTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(DeclarationNode node)
    {
        write(indent, "DECLARATIONNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(SpawnStmtNode node)
    {
        write(indent, "SPAWNSTMTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(YieldStmtNode node)
    {
        write(indent, "YIELDSTMTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ChanWriteNode node)
    {
        write(indent, "CHANWRITENODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ChanReadStmtNode node)
    {
        write(indent, "CHANREADSTMTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(FuncCallComplexNode node)
    {
        write(indent, "FUNCCALLCOMPLEXNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(FuncCallNode node)
    {
        write(indent, "FUNCCALLNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(MemberAccessesNode node)
    {
        write(indent, "MEMBERACCESSESNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(MemberAccessNode node)
    {
        write(indent, "MEMBERACCESSNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(BoolExprNode node)
    {
        write(indent, "BOOLEXPRNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(TrueExprNode node)
    {
        write(indent, "TRUEEXPRNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(FalseExprNode node)
    {
        write(indent, "FALSEEXPRNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ParenExprNode node)
    {
        write(indent, "PARENEXPRNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ExprStmtNode node)
    {
        write(indent, "EXPRSTMTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ExprNode node)
    {
        write(indent, "EXPRNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(MatchStmtNode node)
    {
        write(indent, "MATCHSTMTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(MatchCaseNode node)
    {
        write(indent, "MATCHCASENODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(RangeMatchNode node)
    {
        write(indent, "RANGEMATCHNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(MatchIsNode node)
    {
        write(indent, "MATCHISNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(CharMatchNode node)
    {
        write(indent, "CHARMATCHNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(StringMatchNode node)
    {
        write(indent, "STRINGMATCHNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(NumMatchNode node)
    {
        write(indent, "NUMMATCHNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(NumRangeMatchNode node)
    {
        write(indent, "NUMRANGEMATCHNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(CharRangeMatchNode node)
    {
        write(indent, "CHARRANGEMATCHNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(VariableTypePairNode node)
    {
        write(indent, "VARIABLETYPEPAIRNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ChanReadNode node)
    {
        write(indent, "CHANREADNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(SumNode node)
    {
        write(indent, "SUMNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ProductNode node)
    {
        write(indent, "PRODUCTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ValueNode node)
    {
        write(indent, "VALUENODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(SumOpNode node)
    {
        write(indent, "SUMOPNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(MulOpNode node)
    {
        write(indent, "MULOPNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(NumberNode node)
    {
        write(indent, "NUMBERNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(CharLitNode node)
    {
        write(indent, "CHARLITNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(StringLitNode node)
    {
        write(indent, "STRINGLITNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(IntNumNode node)
    {
        write(indent, "INTNUMNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(FloatNumNode node)
    {
        write(indent, "FLOATNUMNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(IdentifierNode node)
    {
        write(indent, "IDENTIFIERNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(IdTupleNode node)
    {
        write(indent, "IDTUPLENODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(TypeIdNode node)
    {
        write(indent, "TYPEIDNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ChanTypeNode node)
    {
        write(indent, "CHANTYPENODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ArrayTypeNode node)
    {
        write(indent, "ARRAYTYPENODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(PointerDeclNode node)
    {
        write(indent, "POINTERDECLNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(DynArrayDeclNode node)
    {
        write(indent, "DYNARRAYDECLNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(SetTypeNode node)
    {
        write(indent, "SETTYPENODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(HashTypeNode node)
    {
        write(indent, "HASHTYPENODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(TypeTupleNode node)
    {
        write(indent, "TYPETUPLENODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(UserTypeNode node)
    {
        write(indent, "USERTYPENODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(BasicTypeNode node)
    {
        write(indent, "BASICTYPENODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(TemplateInstantiationNode node)
    {
        write(indent, "TEMPLATEINSTANTIATIONNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(TemplateParamNode node)
    {
        write(indent, "TEMPLATEPARAMNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(TemplateParamListNode node)
    {
        write(indent, "TEMPLATEPARAMLISTNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(TemplateParamSingleNode node)
    {
        write(indent, "TEMPLATEPARAMSINGLENODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(TemplateIdNode node)
    {
        write(indent, "TEMPLATEIDNODE");
        if ("type" in node.data)
        {
            write(": ", node.data["type"].get!string);
        }
        writeln();
        indent ~= "  ";
        foreach (child; node.children)
        {
            child.accept(this);
        }
        indent = indent[0..$-2];
    }
    void visit(ASTTerminal node)
    {
        writeln(indent, "[", node.token, "]: ", node.index);
    }
}
