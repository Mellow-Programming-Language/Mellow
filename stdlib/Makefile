MELLOW_INTERNAL = mellow_internal.h mellow_internal.c
STDLIB = stdc stdlib.o core.o conv.o io.o string.o trie.o path.o
COMPILER = ../compiler

CC ?= gcc
# CC_FLAGS = -g -pg -Wall
CC_FLAGS = -g -pg -Wall
CXX ?= g++
CXX_FLAGS = -std=c++11 -Wall

all: $(STDLIB)

conv.o: stdconv.h stdconv.c $(MELLOW_INTERNAL) conv.mlo
	$(CC) $(CC_FLAGS) -c stdconv.c -o stdconv.o
	$(COMPILER) --stdlib="../stdlib" -c conv.mlo -o conv_mlo.o
	ld -r stdconv.o conv_mlo.o -o conv.o

core.o: stdcore.c
	$(CC) $(CC_FLAGS) -c stdcore.c -o core.o

io.o: stdio.c stdio.h $(MELLOW_INTERNAL)
	ld -r stdio.o -o io.o

path.o: path.mlo
	$(COMPILER) --stdlib="../stdlib" -c path.mlo -o path_mlo.o
	ld -r path_mlo.o -o path.o

string.o: stdstring.h stdstring.c $(MELLOW_INTERNAL) string.mlo
	$(CC) $(CC_FLAGS) -c stdstring.c -o stdstring.o
	$(COMPILER) --stdlib="../stdlib" -c string.mlo -o string_mlo.o
	ld -r stdstring.o string_mlo.o -o string.o

trie.o: trie.mlo
	$(COMPILER) --stdlib="../stdlib" -c trie.mlo -o trie_mlo.o
	ld -r trie_mlo.o -o trie.o

trie_unittest: trie_unittest.mlo trie.mlo
	$(COMPILER) --unittest --stdlib="../stdlib" \
		--runtime="../runtime/runtime.o" trie_unittest.mlo \
		-o trie_unittest

hash.o: hash.h hash.cpp
	$(CXX) $(CXX_FLAGS) -c hash.cpp -o hash.o

mellow_internal.o: $(MELLOW_INTERNAL)
	$(CC) $(CC_FLAGS) -c mellow_internal.c -o mellow_internal.o

stdlib.o: stdio.o stdconv.o hash.o mellow_internal.o
	ld -r hash.o mellow_internal.o -o stdlib.o

.PHONY: stdc
stdc:
	make -C c

.PHONY: clean
clean:
	rm -f *.o

.PHONY: realclean
realclean: clean

