all: runtime.o

runtime.o: callFunc.o scheduler.o tls.o
	ld -L /usr/lib -lpthread -r callFunc.o scheduler.o tls.o -o runtime.o

callFunc.o: callFunc.asm
	nasm -f elf64 callFunc.asm

scheduler.o: scheduler.c scheduler.h
	gcc -pthread -c scheduler.c

tls.o: tls.asm
	as tls.asm -o tls.o

# Provided so that the invocation used to produce tls.asm is recorded
tls.asm: tls.c
	gcc -O3 -pthread -S -c tls.c -masm=intel -o tls.asm

clean:
	-rm *.o
