The Mellow Programming Language
===============================

Mellow is a language that is designed to give the programmer the tools they need
to get the job done, without getting in their way. It attempts to offer
flexibility everywhere it can, and tries to stay out of the way of the
development process. It exists as nothing more than a tool to accomplish
some task, rather than a lifestyle one must adopt.

Features
--------

Note that not all of these features are implemented yet. The README is the best
source for the list of implemented and unimplemented features.

* Compiled to x86 assembly
  * The x86 is directly generated, so optimizations are limited
  * Transitioning to LLVM is a potential end-goal
* Statically typed
* Simple type inference
* Reference-counted garbage collection
* Lambdas
* Simple templating
  * Functions and data structures can be templated over one or more types
  * Not a Turing-complete mess, for better or worse
  * Not as powerful as D
* Message passing concurrency system, in the style of Go
  * Full M:N scheduling, if multi-threading is enabled when compiling the
  compiler
* Multiple-return from functions
  * Can be created and unpacked with simple syntax, but tuples cannot be
  passed around as a distinct value.
* No exceptions
  * No exceptions
* D-style scope statements
  * Blocks of code whose execution is deferred to the end of the function it
  is enclosed within
* Structs, in the style of C
  * Simple data containers
* Sum types, in the style of ML languages
* Pattern matching, using the `match` statement
  * Can pattern-match on:
    * Basic types
    * Tuples, with implicit unpacking
    * Type constructors for sum types
    * Arrays
      * Can match starting from the beginning or the end of the array
  * The patterns matched can include:
    * Variable bindings
    * Value literals
    * Wildcards
* Maybe type
  * Where it makes sense, the standard library uses Maybe to make guarantees
* Uniform Function Call Syntax
  * Thank you, D!
* Optional parentheses for function calls when there are no arguments
* Dynamic arrays that know their length
  * No support for static arrays
  * Array space can be preallocated for basic types
* Associative arrays (hash maps), in the style of D
* Sets
  * Set operations are defined:
    * Union
    * Intersection
    * Difference
* Uniform `in` operator that can check membership within:
  * Dynamic arrays
  * Associative arrays
    * Checks for existence of a key
  * Sets
* `ref` and `const` are the only two function-parameter storage classes
* Function pointers and closures
  * Both style of function pointers are treated as values that can be passed
  around and stored as with any other value type
* A dead-simple FFI to C with the `extern` declaration
* Declaration and assignment is allowed within conditional expressions
  * `if`, `while`, `match`, `for`, `foreach`
  * This means a variable, whose value is dependent on a condition that
  also drives the if statement execution, does not need to erroneously
  live outside of the scope of the if statement just to exist

Keywords and Operators
----------------------

* Assignment operators:
  * `=`  `x = y`
  * `+=`
  * `-=`
  * `*=`
  * `/=`
* Declare and assign, implies type inference:
  * `:=` `x := 2 + 3;`
* Logical operators:
  * `&&`
  * `||`
  * `!` (unary)
* Comparison operators:
  * `==` `x == y`
  * `<=`
  * `>=`
  * `!=`
  * `in`
* Arithmetic operators:
  * `+` `x + y`
  * `-`
  * `*`
  * `/`
* `if`
* `else if`
* `else`

            if (1 > 2 || myString != "Hello!") {
                writeln("if!");
            }
            else if (false) {
                writeln("else if!");
            }
            else if (!true) {
                writeln("else if!");
            }
            else {
                writeln("else!");
            }

* `match`

            match (myArray[0]) {
                x if (0 < x < 5) :: writeln("Is: " ~ intToString(val));
                10               :: writeln("Ten!");
                _                :: writeln("Oh well");
            }
            match (tree := binaryTree(); tree) {
                Branch (Leaf, _, Leaf) ::
                    writeln("No children!");
                Branch (Branch (Leaf, _, Leaf), _, _) ::
                    writeln("Left child has no children!");
                Leaf ::
                    writeln("Leaf!");
                _ ::
                    writeln("Some other case!");
            }

* `struct`

            struct MyStruct {
                x: string;
                y: int;
            }
            struct OtherStruct (T, U) {
                x: T;
                y: U;
            }

  * Constructing a struct value:

              s1 := MyStruct {
                  x = "Hello!",
                  y = 10
              };
              s2 := OtherStruct!(string, int) {
                  x = "Goodbye!",
                  y = 20
              };

* `variant`

            variant Tree {
                Branch (Tree, int, Tree),
                Leaf
            }
            variant Maybe(T) {
                Some (T),
                None
            }

  * Constructing a variant value:

            t := Branch (
                Branch (
                    Leaf, 10, Leaf
                ), 20, Leaf
            );
            m := Some!MyStruct(MyStruct { x = 1, y = "2" });
            n := None!int;

* func

            func myFunc(x: int): (int, int) {
                return (2 * x, 4 * x);
            }
            func identity(T)(x: T): T {
                return x;
            }

  * Calling a function:

              (x, y) := myFunc(10);
              me := identity!int(10);

* fn (lambda syntax)

            fn (x: uint) => x + 1

* Template instantiation:
  * `!` ("binary") `Maybe!(int)`, `Maybe!int`, `MyStruct!(int, string)`
* Channel operators
  * `<-`  (channel read)  `x = <-myChan;`
  * `<-=` (channel write) `myChan <-= x;`
* spawn

            ch := chan!int;
            spawn bigProc(ch);
            x := <-ch;

* Aggregate data declarations:
  * myDynamicArray: `[]int`
  * myHashWithStringKeysAndIntValues: `[string]int`
  * mySet: `<>uint`

Semantics
---------
* Precedence table. Anything on the same line is the same precendence, and
  anything on a line below another line has more precedence than the
  preceeding line. If the following line is indented over from the previous
  line, it is considered part of the previous line:

        =                         (binop, assignment, right-associative)
        ||                        (binop, logical OR)
        &&                        (binop, logical AND)
        !                         (unary, logical NOT, right-associative)
        <= >= < > == != in        (binop, comparison)
            <|> <&> <^> <-> <in>
        |                         (binop, bitwise OR)
        ^                         (binop, bitwise XOR)
        &                         (binop, bitwise AND)
        << >>                     (binop, bitwise shift)
        + - ~                     (binop, arithmetic sum or concatenate)
        * / %                     (binop, arithmetic mult, div, mod)
        <Literal Value>

  * A literal value is defined as:
    * A boolean literal, `true`, `false`
    * The result of an expression in parentheses, `(<expression>)`
    * A literal number, `0`, `56`, `5.1`, `5.`, `.1`
    * A literal string, `"Hello!"`
    * The result of a channel read, `<-myChan`
    * A variable
    * The result of indexing into an aggregate type
    * A function call
    * Accessing a type attribute, ie `.length` on a dynamic array, or a struct
    member
    * A struct or variant constructor
    * A lambda expression
  * Indexing into a variable, or slicing into a variable, can involve an
    arbitrarily complex expression, as long as it evaluates to a value
    of the type expected by the sliceable variable
      * Dynamic arrays must be indexed using an `int`
      * Associative arrays must be indexed using a value of the type used
      as the keys for the associative array
* Set operators:
  * union,                `A <|> B`
    * Yields a set containing all elements from both sets
  * intersection,         `A <&> B`
    * Yields a set containing only the elements contained in both sets
  * anti-intersection,    `A <^> B`
    * Yields a set containing only the elements from each set that are
      not present in both sets
  * difference,           `A <-> B`
    * Yields the subset of A after the intersection of A and B is
      removed from A
  * subset test,          `A <in> B`
    * Yields a boolean value representing whether A is a subset of B.
      To determine if A is a proper subset of B, combine with the `==`
      operator
  * equality,             `A == B`
    * Yields a boolean value representing whether A is equivalent to B
  * inequality,           `A != B`
    * Yields a boolean value representing whether A is not equivalent
      to B
* `if`
  * It is possible to declare a new variable inside the conditional
  component, assigning some expression to the new variable.

            if (x := myFunc(); x == 5) {
                writeln("x [" ~ intToString(x) ~ "]");
            }
            else if (y := myFunc(); y == 5) {
                writeln("Not x [", x, "], but y [", y, "]")
            }
            else {
                writeln("Neither of [", x, ", ", y, "]");
            }

* `match`
  * Match against the result of some expression.

            match (slice := array[0..index]; slice) {
                [1, 2, 3, ..] ::
                    writeln("Sequential start!");
                [.., 3, 2, 1] ::
                    writeln("Sequential end!");
                [4, 5, 6, .. as tail] ::
                    writeln("Tail is bound to the rest!");
                _ if (5 in slice) ::
                    writeln("Contains 5!");
                _ ::
                    writeln("Welp!");
            }
