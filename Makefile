all: compiler runtime/runtime.o stdlib/stdlib.o

compiler: main.d Function.d FunctionSig.d Record.d parser.d visitor.d\
		  ASTUtils.d typedecl.d utils.d CodeGenerator.d ExprCodeGenerator.d
	dmd -ofcompiler main.d Function.d FunctionSig.d Record.d parser.d\
		visitor.d ASTUtils.d typedecl.d utils.d CodeGenerator.d\
		ExprCodeGenerator.d

runtime/runtime.o:
	make -C runtime

stdlib/stdlib.o:
	make -C stdlib

parser.d: lang.peg ParserGenerator/parserGenerator
	ParserGenerator/parserGenerator < lang.peg > parser.d

ParserGenerator/parserGenerator: ParserGenerator
	make -C ParserGenerator

ParserGenerator:
	git clone https://github.com/CollinReeser/ParserGenerator.git

clean:
	rm compiler
	rm *.o
	rm runtime/*.o
	rm stdlib/*.o

realclean: clean
	rm -rf ParserGenerator
