MELLOW_INTERNAL = mellow_internal.h mellow_internal.c
STDLIB = stdlib.o core.o conv.o io.o string.o trie.o path.o
COMPILER = ../compiler

all: $(STDLIB)

conv.o: stdconv.h stdconv.c $(MELLOW_INTERNAL) conv.mlo
	gcc -c stdconv.c -o stdconv.o
	$(COMPILER) --stdlib="../stdlib" -c conv.mlo -o conv_mlo.o
	ld -r stdconv.o conv_mlo.o -o conv.o

core.o: stdcore.c
	gcc -c stdcore.c -o core.o

io.o: stdio.c stdio.h $(MELLOW_INTERNAL)
	ld -r stdio.o -o io.o

path.o: path.mlo
	$(COMPILER) --stdlib="../stdlib" -c path.mlo -o path_mlo.o
	ld -r path_mlo.o -o path.o

string.o: stdstring.h stdstring.c $(MELLOW_INTERNAL) string.mlo
	gcc -c stdstring.c -o stdstring.o
	$(COMPILER) --stdlib="../stdlib" -c string.mlo -o string_mlo.o
	ld -r stdstring.o string_mlo.o -o string.o

trie.o: trie.mlo
	$(COMPILER) --stdlib="../stdlib" -c trie.mlo -o trie_mlo.o
	ld -r trie_mlo.o -o trie.o

trie_unittest: trie_unittest.mlo trie.mlo
	$(COMPILER) --unittest --stdlib="../stdlib" \
		--runtime="../runtime/runtime.o" trie_unittest.mlo \
		-o trie_unittest

mellow_internal.o: $(MELLOW_INTERNAL)
	gcc -c mellow_internal.c -o mellow_internal.o

stdlib.o: stdio.o stdconv.o mellow_internal.o
	ld -r mellow_internal.o -o stdlib.o

.PHONY: clean
clean:
	rm -f *.o

.PHONY: realclean
realclean: clean

