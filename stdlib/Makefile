all: stdlib.o

stdio.o: mellow_internal.h mellow_internal.c stdio.c stdio.h
	gcc -c stdio.c -o stdio.o

stdconv.o: stdconv.h mellow_internal.h mellow_internal.c
	gcc -c stdconv.c -o stdconv.o

mellow_internal.o: mellow_internal.h mellow_internal.c
	gcc -c mellow_internal.c -o mellow_internal.o

stdlib.o: stdio.o stdconv.o mellow_internal.o
	ld -r stdio.o stdconv.o mellow_internal.o -o stdlib.o
