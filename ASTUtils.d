import std.stdio;
import std.variant;
import std.algorithm;
import std.conv;
import std.range;
import std.array;
import parser;
import visitor;
import typeInfo;

private struct Found
{
    bool isValid;
    ASTNode node;
    this(bool isValid, ASTNode node)
    {
        this.isValid = isValid;
        this.node = node;
    }
}

// Given a search function which takes an ASTNode and returns a boolean,
// attempt to search the tree given a start node for that node-type
template search(alias searchFunction)
{
    // Find the next node, not including the one passed in, that satisfies
    // the check
    ASTNode findNext(ASTNode node)
    {
        // Try to get a nonterminal cast, as that is generally what we're trying
        // to work with
        auto nonterminal = cast(ASTNonTerminal)node;
        // Must be a terminal node, try to grab parent
        if (nonterminal is null)
        {
            auto result = upSearch(node);
            if (result.isValid)
            {
                return result.node;
            }
            return null;
        }
        // Is a nonterminal node, so attempt to search the subtree for the node
        // type we're looking for
        foreach (child; nonterminal.children)
        {
            auto result = findNode(child);
            if (result.isValid)
            {
                return result.node;
            }
        }
        auto result = upSearch(node);
        if (result.isValid)
        {
            return result.node;
        }
        return null;
    }

    // Given a node, attempt to collect all nodes in the tree that satisfy the
    // condition. The search will include the subtree of the node and all nodes
    // up and to the right of the node, as well as checking the node itself
    ASTNode[] findAll(ASTNode node)
    {
        ASTNode[] nodes;
        if (searchFunction(node))
        {
            nodes ~= node;
        }
        ASTNode result = findNext(node);
        while (result !is null)
        {
            nodes ~= result;
            result = findNext(result);
        }
        return nodes;
    }

    // Given a node, take the node's parent, use only the children past this
    // node to search down the tree with, and keep moving to successively higher
    // parents until a child subtree yields a successful search or we've
    // exhausted the tree. This function assumes that the passed in node does
    // not satisfy the search
    private Found upSearch(ASTNode node)
    {
        bool found = false;
        while (!found)
        {
            // Try to find what we're looking for from the parent's
            // perspective, skipping the child
            auto result = findAfter(node);
            // We found something, so return it
            if (result.isValid)
            {
                return result;
            }
            // Grab the parent node
            auto parent = node.parent;
            // There is no parent, therefore we cannot continue in our search
            if (parent is null)
            {
                // Couldn't find anything
                return Found(false, null);
            }
            // We didn't find anything, so loop using the parent as the base
            // node
            node = parent;
        }
        return Found(false, null);
    }

    // Attempts a search by taking the parent of the passed node, finding the
    // children to the "right" of the passed node from the passed node's parent,
    // and searching those. Effectively skips the passed node in an up-one-level
    // search
    private Found findAfter(ASTNode skipChild)
    {
        auto parent = skipChild.parent;
        // If there is no parent to this node, then there's is nothing
        // "to the right" of this node. It has no siblings! So return failure
        if (parent is null)
        {
            return Found(false, null);
        }
        auto children = parent.children;
        // Get the index within which the skip child resides
        auto index = 0;
        while (children[index] != skipChild)
        {
            index++;
        }
        // Increment to one past the skipChild
        index++;
        // Only loop over the children past the skip child
        auto validChildren = children[index..$] ;
        foreach (child; validChildren)
        {
            // Search the child subtree
            auto result = findNode(child);
            // If we found it, return it
            if (result.isValid)
            {
                return result;
            }
        }
        // We didn't find anything
        return Found(false, null);
    }

    // This does the actual search in that it applies the passed searchFunction
    // to locate the node type
    private Found findNode(ASTNode node)
    {
        // Is this node of the type we're looking for? Return it!
        if (searchFunction(node))
        {
            return Found(true, node);
        }
        // Otherwise, cast to a type we can work with
        auto nonterminal = cast(ASTNonTerminal)node;
        if (nonterminal is null)
        {
            // If it's not the type we're looking for and it's not an
            // ASTNonTerminal (meaning it has no children), then we didn't find
            // anything
            return Found(false, null);
        }
        // Search the children for the node we're looking for
        foreach (child; nonterminal.children)
        {
            // Search the child subtree
            auto result = findNode(child);
            // If we found it, return it
            if (result.isValid)
            {
                return result;
            }
        }
        return Found(false, null);
    }
}

unittest
{
    auto source =
q"HERE
func strings()
{
    str := "Hello!";
    str = `World!`;
    str = "Testing " "things!";
    str = `Testing ` `things!`;
    str = "Does " `this ` "work?";
    a := 0;
    b: int = 0;
}
HERE";
    alias searchStringLit = search!(
        a => typeid(a) == typeid(StringLitNode)
    );
    alias searchDeclInfer = search!(
        a => typeid(a) == typeid(DeclTypeInferNode)
    );
    alias searchAssignExisting = search!(
        a => typeid(a) == typeid(AssignExistingNode)
    );
    alias searchDecl = search!(
        a => typeid(a) == typeid(DeclarationNode)
    );
    auto topNode = new Parser(source).parse();
    assert(topNode !is null);
    assert(searchStringLit.findAll(topNode).length == 5);
    assert(searchDeclInfer.findAll(topNode).length == 2);
    assert(searchAssignExisting.findAll(topNode).length == 4);
    assert(searchDecl.findAll(topNode).length == 3);
}
