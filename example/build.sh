#!/bin/sh

eval "`bob --start || echo exit`"

readenv CFLAGS -O3 -std=c99

bob mkdir -p output

bob --pushd output

bob gcc $CFLAGS -c ../square.c -o square.o
bob gcc $CFLAGS -c ../hello.c -o hello.o

bob gcc hello.o square.o -o hello

