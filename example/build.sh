#!/bin/sh

eval "`bob --start || echo exit`"

readenv CFLAGS -O3 -std=c99

bob mkdir -p output

bob gcc $CFLAGS -c square.c -o output/square.o
bob gcc $CFLAGS -c hello.c -o output/hello.o

bob gcc output/hello.o output/square.o -o output/hello

