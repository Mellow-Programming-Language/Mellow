Changelog
=========

0.9.2
-----

* Fixed being unable to append a string to an array of strings

* Updated README to note new location of the Parser Generator within the
Mellow Programming Language organization

0.9.1
-----

* Fixed not being able to `spawn` templated functions

0.9.0
-----

* Implemented full module system
  * `import` statement used to import modules: `import std.io;`
  * All type definitions and function signatures from only the scope of the
  imported module are imported.
  * The full import graph is determined before files are compiled.
  * Simply compiling the `main.mlo` of a program will correctly compile the full
  program.

* Introduced several importable standard library files, under `std`
  * `io`
    * `extern struct File`
    * `writeln`
    * `write`
    * `readln`
    * `mellow_fopen`
    * `mellow_fclose`
    * `mellow_freadln`
  * `conv`
    * `ord`
    * `chr`
    * `charToString`
    * `stringToChars`
    * `charsToString`
    * `intToString`
  * `core`
    * `variant Maybe(T)`
    * `struct Pair(T, U)`
  * `path`
    * `basename`
    * `dirname`
  * `string`
    * `join`
    * `toUpper`, `toLower`
    * `lastIndex`, `firstIndex`
  * `trie`
    * A templated implementation of the trie datastructure
  * Note that all of these modules are subject to heavy changes
  and additions

* Implemented the `assert` statement: `assert(false, "Assert failure!")`

* Implemented the `--release` compiler flag that disables `assert` statements

* Implemented runtime array out-of-bounds assert checks
  * Disabled by the `--release` flag

* Implemented the `unittest` block: `unittest {}`
  * Unittest blocks are only compiled in if the `--unittest` flag is used
  * All unittests are executed prior to program execution proper

* Reimplemented array append and slice operations in C

* Implemented automatic stack growth
  * A function prologue ensures that green threads can grow their own stack
  as necessary

* Greatly expanded the testing infrastructure
  * Ensure the multithreaded runtime passes the full testing suite
  * Added many tests

* The `--S` switch also generates the new "entry point" asm file

* Added more error messages, and improved existing ones
  * Also added line information most or all relevant error messages

* Many bug fixes
  * Fixes in type resolution (including seemingly fully fixing recursive types)
  * Many others

0.8.11
------

* Implemented short-circuiting for `&&` and `||`

0.8.10
------

* Implemented `break` and `continue` for `while` and `foreach` loops

* Implemented `+=`, `-=`, `*=`, `/=`, `%=` for integer types

0.8.9
-----

* Fixed being unable to call attributes on expressions that resolve to types
that have those attributes

* Fixed a bug where structs and variants with more than one template argument
can fail to be instantiated during typechecking

0.8.8
-----

* Added line and column information for type errors involving numeric
type-promotion

0.8.7
-----

* Added line and column information for many typechecking errors

0.8.6
-----

* Fixed being able to pre-allocate arrays of structs and variants

0.8.5
-----

* Implemented being able to assign an empty array, `[]`, to an array-type
variable to clear it

* Implemented code generation for declaration-assignment, i.e., `a: int = 0;`

* Added `chr(c: int): char` conversion function to `std.conv`

* Improved code generation for `.length` attribute access on arrays

* Improvements and additions to the testing infrastructure

0.8.4
-----

* Documentation improvements

0.8.3
-----

* (Project Management) Added support for Travis CI regression testing on commit

0.8.2
-----

* Fixed taking the `.length` of a slice expression segfaulting

0.8.1
-----

* Added rudimentary testing infrastructure for the compiler itself

* Fixed backslashes in one string in a chain of string appends appearing to
cause the remaining appends in the chain to no-op

* Implemented the semantics of "best effort" array slicing, where nonsensical
and partially out-of-bounds array slices will yield empty arrays and arrays up
to those bounds, respectively

* Fixed being unable to pass empty array literals, `[]`, as arguments to
functions, struct constructors, and variant constructors
