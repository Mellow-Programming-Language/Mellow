all: io.o conv.o stdlib.o core.o string.o

core.o: core.c
	gcc -c core.c -o core.o

stdio.o: stdio.c stdio.h mellow_internal.h mellow_internal.c
	gcc -c stdio.c -o stdio.o

io.o: stdio.o
	ld -r stdio.o -o io.o

stdconv.o: stdconv.h stdconv.c mellow_internal.c mellow_internal.h
	gcc -c stdconv.c -o stdconv.o

conv_mlo.o: conv_mlo.mlo
	../compiler -c conv_mlo.mlo

conv.o: stdconv.o conv_mlo.o
	ld -r stdconv.o conv_mlo.o -o conv.o

stdstring.o: stdstring.h stdstring.c mellow_internal.h mellow_internal.c
	gcc -c stdstring.c -o stdstring.o

string_mlo.o: string_mlo.mlo
	../compiler -c string_mlo.mlo

string.o: stdstring.o string_mlo.o
	ld -r stdstring.o string_mlo.o -o string.o

mellow_internal.o: mellow_internal.h mellow_internal.c
	gcc -c mellow_internal.c -o mellow_internal.o

stdlib.o: mellow_internal.o
	ld -r mellow_internal.o -o stdlib.o
