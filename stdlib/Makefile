MELLOW_INTERNAL = mellow_internal.h mellow_internal.c
STDLIB = stdlib.o core.o conv.o io.o string.o path.o

all: $(STDLIB)

conv.o: stdconv.o conv_mlo.o
	ld -r stdconv.o conv_mlo.o -o conv.o

core.o: stdcore.c
	gcc -c stdcore.c -o core.o

io.o: stdio.o
	ld -r stdio.o -o io.o

string.o: stdstring.o string_mlo.o
	ld -r stdstring.o string_mlo.o -o string.o

path.o: path_mlo.o
	ld -r path_mlo.o -o path.o

stdconv.o: stdconv.h stdconv.c $(MELLOW_INTERNAL)
	gcc -c stdconv.c -o stdconv.o

conv_mlo.o: conv_mlo.mlo
	../compiler --stdlib="../stdlib" -c conv_mlo.mlo

path_mlo.o: path_mlo.mlo
	../compiler --stdlib="../stdlib" -c path_mlo.mlo

stdio.o: stdio.c stdio.h $(MELLOW_INTERNAL)
	gcc -c stdio.c -o stdio.o

stdstring.o: stdstring.h stdstring.c $(MELLOW_INTERNAL)
	gcc -c stdstring.c -o stdstring.o

string_mlo.o: string.mlo
	../compiler --stdlib="../stdlib" -c string.mlo -o string_mlo.o

stdlib.o: stdio.o stdconv.o mellow_internal.o
	ld -r mellow_internal.o -o stdlib.o

mellow_internal.o: $(MELLOW_INTERNAL)
	gcc -c mellow_internal.c -o mellow_internal.o

.PHONY: clean
clean:
	rm -f *.o

.PHONY: realclean
realclean:

