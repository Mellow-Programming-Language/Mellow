all: runtime.o

runtime.o: callFunc.o scheduler.o
	ld -r callFunc.o scheduler.o -o runtime.o

runtime_multithread.o: callFunc_multithread.o scheduler_multithread.o tls.o
	ld -L /usr/lib -lpthread -r callFunc_multithread.o scheduler_multithread.o \
	tls.o -o runtime_multithread.o

callFunc.o: callFunc.asm
	nasm -f elf64 callFunc.asm

callFunc_multithread.o: callFunc_multithread.asm
	nasm -f elf64 callFunc_multithread.asm

scheduler.o: scheduler.c scheduler.h
	gcc -c scheduler.c

scheduler_multithread.o: scheduler.c scheduler.h
	gcc -D MULTITHREAD -pthread -c scheduler.c -o scheduler_multithread.o

tls.o: tls.asm
	as tls.asm -o tls.o

# Provided so that the invocation used to produce tls.asm is recorded
tls.asm: tls.c
	gcc -O3 -pthread -S -c tls.c -masm=intel -o tls.asm

clean:
	-rm *.o
