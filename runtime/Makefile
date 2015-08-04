all: runtime.o runtime_multithread.o

CC = gcc
CC_FLAGS = -Wall
ASM = nasm
ASM_FLAGS = -f elf64
CC_MULTITHREAD = -D MULTITHREAD -pthread
# Find all unique directories libpthread-related files exist, and construct a
# string of "-L libdir -L libdir ..."
LD_LIBS = $(shell locate libpthread | xargs dirname | uniq | perl -e 'print join " ", map {$$t = $$_; chomp $$t; "-L $$t"} <STDIN>')
LD_MULTITHREAD = $(LD_LIBS) -lpthread

runtime.o: callFunc.o scheduler.o
	ld -r callFunc.o scheduler.o -o runtime.o

runtime_multithread.o: callFunc_multithread.o scheduler_multithread.o tls.o
	ld $(LD_MULTITHREAD) -r callFunc_multithread.o scheduler_multithread.o \
	tls.o -o runtime_multithread.o

callFunc.o: callFunc.asm
	$(ASM) $(ASM_FLAGS) callFunc.asm

callFunc_multithread.o: callFunc_multithread.asm
	$(ASM) $(ASM_FLAGS) callFunc_multithread.asm

scheduler.o: scheduler.c scheduler.h
	$(CC) $(CC_FLAGS) -c scheduler.c

scheduler_multithread.o: scheduler.c scheduler.h
	$(CC) $(CC_FLAGS) $(CC_MULTITHREAD) -c scheduler.c \
	-o scheduler_multithread.o

tls.o: tls.asm
	as tls.asm -o tls.o

# Provided so that the invocation used to produce tls.asm is recorded
tls.asm: tls.c
	$(CC) $(CC_FLAGS) -O3 -pthread -S -c tls.c -masm=intel -o tls.asm

.PHONY: clean
clean:
	rm -f *.o

.PHONY: realclean
realclean:
