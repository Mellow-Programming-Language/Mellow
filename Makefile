all: compiler runtime/runtime.o stdlib/stdlib.o

compiler: main.d Function.d FunctionSig.d Record.d parser.d visitor.d\
		  ASTUtils.d typedecl.d utils.d CodeGenerator.d ExprCodeGenerator.d\
		  TemplateInstantiator.d
	dmd -ofcompiler main.d Function.d FunctionSig.d Record.d parser.d\
		visitor.d ASTUtils.d typedecl.d utils.d CodeGenerator.d\
		ExprCodeGenerator.d TemplateInstantiator.d

compiler_debug: main.d Function.d FunctionSig.d Record.d parser.d visitor.d\
		  ASTUtils.d typedecl.d utils.d CodeGenerator.d ExprCodeGenerator.d\
		  TemplateInstantiator.d\
		  runtime/runtime.o
	dmd -ofcompiler_debug main.d Function.d FunctionSig.d Record.d parser.d\
		visitor.d ASTUtils.d typedecl.d utils.d CodeGenerator.d\
		ExprCodeGenerator.d TemplateInstantiator.d\
		-debug=COMPILE_TRACE -debug=TRACE

compiler_multithread: main.d Function.d FunctionSig.d Record.d parser.d\
		  visitor.d ASTUtils.d typedecl.d utils.d CodeGenerator.d\
		  ExprCodeGenerator.d TemplateInstantiator.d\
		  runtime/runtime_multithread.o
	dmd -ofcompiler_multithread main.d Function.d FunctionSig.d Record.d\
		parser.d visitor.d ASTUtils.d typedecl.d utils.d CodeGenerator.d\
		ExprCodeGenerator.d TemplateInstantiator.d\
		-version=MULTITHREAD

runtime/runtime.o: runtime/callFunc.asm runtime/scheduler.c runtime/scheduler.h
	make -C runtime

runtime/runtime_multithread.o: runtime/callFunc_multithread.asm\
							   runtime/scheduler.c runtime/scheduler.h
	make runtime_multithread.o -C runtime

stdlib/stdlib.o: stdlib/mellow_internal.c stdlib/mellow_internal.h\
				 stdlib/stdconv.c stdlib/stdconv.h stdlib/stdio.c\
				 stdlib/stdio.h
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
