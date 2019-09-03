The Mellow Programming Language
===============================

[![Build Status](https://travis-ci.org/Mellow-Programming-Language/Mellow.svg?branch=master)](https://travis-ci.org/Mellow-Programming-Language/Mellow)

Mellow is an imperative language that draws influence from D, Go, and
functional languages, among others. This implementation exclusively targets
x86-64 Linux.

Building
--------

The build process assumes that recent versions of the D Language compiler
`dmd`, `gcc`, `g++`, `git`, and the Netwide Assembler `nasm` are installed.

To build the compiler, run `make` in the toplevel project directory. With the
proper dependencies installed, and an internet connection, a simple `make`
should build the full compiler. Note that the `make` process will attempt to
`git clone` a secondary repository (the parser generator project at
https://github.com/Mellow-Programming-Language/ParserGenerator), which is
necessary to build the compiler.

To enable the green threads runtime, `make compiler_multithread` to build a
version of the compiler with those features enabled.

Help
----

`./compiler --help` will provide a summary of options.

Examples
--------

The programs under examples/ demonstrate the syntax and semantics of the Mellow
language.

List of working features:
-------------------------

  * green threads (`spawn`, `yield`)
  * channels (both read and write, with implicit yield)
  * full M:N multithreading scheduler
  * garbage collection
  * modules
  * templates (for functions and struct definitions)
  * recursively-definable, template-able variants/sum-types (ADTs)
  * `match` statements
  * `is` variant-decomposition expressions
  * functions (taking arguments, returning results including multi-return)
  * function pointers
  * variables
  * basic data types: strings, bools, integers
  * arrays: array literals, slice ranges, append semantics, `.length` property
  * control-flow statements (`if`-`else if`-`else`, `while`, `foreach`, etc)
  * `extern func` FFI semantics
  * expressions: comparison operators, logical operators (&&, ||, !), etc.
  * `then`, `else`, `coda` "end block" control-flow blocks


List of unimplemented or broken (but planned) features:
-------------------------------------------------------

  * closures
  * most op-equals operators
  * `in` blocks
  * `out` blocks
  * `const` semantics
  * sets
  * hashes
  * float arithmetic and comparison operators
  * lambdas
