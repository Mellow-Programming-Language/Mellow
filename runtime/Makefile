all: runtime.o

runtime.o: callFunc.o scheduler.o
	ld -r callFunc.o scheduler.o -o runtime.o

callFunc.o: callFunc.asm
	nasm -f elf64 callFunc.asm

scheduler.o: scheduler.c scheduler.h
	gcc -c scheduler.c

realclean:
	-rm *.o
