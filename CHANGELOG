Changelog
=========

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
