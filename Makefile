FILES = main.d Function.d FunctionSig.d Record.d parser.d visitor.d\
		ASTUtils.d typedecl.d utils.d CodeGenerator.d ExprCodeGenerator.d\
		TemplateInstantiator.d Namespace.d

.PHONY: all
all: compiler runtime stdlib

.PHONY: test
test:
	make
	perl test/compilable.pl compiler
	perl test/executable.pl compiler
	perl test/runtime.pl compiler
	make compiler_multithread
	perl test/compilable.pl compiler_multithread
	perl test/executable.pl compiler_multithread
	perl test/runtime.pl compiler_multithread

compiler: $(FILES)
	dmd -ofcompiler $(FILES)

compiler_debug: $(FILES)
	dmd -ofcompiler_debug $(FILES) -debug=COMPILE_TRACE -debug=TRACE

compiler_multithread: $(FILES)
	dmd -ofcompiler_multithread $(FILES) -version=MULTITHREAD
	make -C stdlib realclean
	make -C stdlib COMPILER="../compiler_multithread"

.PHONY: runtime
runtime:
	make -C runtime

.PHONY: stdlib
stdlib:
	make -C stdlib

parser.d: lang.peg ParserGenerator/parserGenerator
	ParserGenerator/parserGenerator < lang.peg > parser.d

ParserGenerator/parserGenerator: ParserGenerator
	make -C ParserGenerator

ParserGenerator:
	git clone https://github.com/CollinReeser/ParserGenerator.git

.PHONY: clean
clean:
	rm -f *.o
	make -C stdlib clean
	make -C runtime clean

.PHONY: realclean
realclean: clean
	rm -f compiler
	rm -f compiler_debug
	rm -f compiler_multithread
	make -C stdlib realclean
	make -C runtime realclean

.PHONY: ultraclean
ultraclean: realclean
	rm -rf ParserGenerator
