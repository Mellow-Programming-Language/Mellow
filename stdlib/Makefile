all: stdlib.o

stdio.o: mellow_internal.h stdio.c stdio.h
	gcc -c stdio.c -o stdio.o

stdconv.o: stdconv.h
	gcc -c stdconv.c -o stdconv.o

stdlib.o: stdio.o stdconv.o
	ld -r stdio.o stdconv.o -o stdlib.o
