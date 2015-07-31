all: io.o conv.o stdlib.o

stdio.o: stdio.c stdio.h mellow_internal.h mellow_internal.c
	gcc -c stdio.c -o stdio.o

io.o: stdio.o
	ld -r stdio.o -o io.o

stdconv.o: stdconv.h mellow_internal.c mellow_internal.h
	gcc -c stdconv.c -o stdconv.o

conv.o: stdconv.o
	ld -r stdconv.o -o conv.o

mellow_internal.o: mellow_internal.h mellow_internal.c
	gcc -c mellow_internal.c -o mellow_internal.o

stdlib.o: mellow_internal.o
	ld -r mellow_internal.o -o stdlib.o
