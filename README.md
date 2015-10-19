The Mellow Programming Language
===============================

[![Build Status](https://travis-ci.org/Mellow-Programming-Language/Mellow.svg?branch=master)](https://travis-ci.org/Mellow-Programming-Language/Mellow)

Mellow is an imperative language that draws influence from D, Go, and functional
languages, among others. This implementation exclusively targets x86-64 Linux.

Building
--------

The build process assumes that the D Language compiler `dmd`, `gcc`, `git`, and
the Netwide Assembler `nasm` are installed.

To build the compiler, run `make` in the toplevel project directory. With the
proper dependencies installed, and an internet connection, a simple `make`
should build the full compiler. Note that the `make` process will attempt to
`git clone` a secondary repository (the parser generator project at
https://github.com/Mellow-Programming-Language/ParserGenerator), which is
necessary to build the compiler.

Help
----

`./compiler --help` will provide a summary of options.

Examples
--------

The programs under examples/ demonstrate the syntax and semantics of the Mellow
language.

List of working features:
------------------------------------

  * variables
  * functions
  * function arguments
  * function return values (including multiple-return)
  * `if`, `else if`, `else` statements with optional variable declarations
  * `while` loops with optional variable declarations
  * `foreach` loops with optional index variable
  * strings
  * bools
  * integers
  * floats can be declared
  * array literals
  * array slice ranges
  * array append semantics
  * green threads (`spawn`, `yield`)
  * channels (both read and write, with implicit yield)
  * expressions
  * `extern func` FFI semantics
  * integer comparison operators
  * logical operators (&&, ||, !)
  * array `.length` property
  * templated structs
  * templated, recursively-defined variants
  * `is` expressions
  * string comparison operators
  * function templating
  * `match` statements
  * full M:N multithreading scheduler
  * module system


List of unimplemented or broken features:
-----------------------------------------

  * closures
  * garbage collection
  * most op-equals operators
  * `in` blocks
  * `out` blocks
  * `const` semantics
  * `for` statement
  * sets
  * hashes
  * function pointers
  * float comparison operators
  * float arithmetic
  * lambdas
