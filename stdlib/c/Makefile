STDLIB = conv.o
COMPILER = ../../compiler


CC ?= gcc
CC_FLAGS = -Wall
CXX ?= g++
CXX_FLAGS = -std=c++11 -Wall

all: $(STDLIB)

conv.o: conv.c conv.h
	$(CC) $(CC_FLAGS) -c conv.c -o conv_c.o
	$(COMPILER) --stdlib="../../stdlib" -c conv.mlo -o conv_mlo.o
	ld -r conv_c.o conv_mlo.o -o conv.o

.PHONY: clean
clean:
	rm -f *.o

.PHONY: realclean
realclean: clean
