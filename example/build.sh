#!/bin/sh

eval "`bob --start || echo exit`"

bob mkdir -p output

bob gcc -c square.c -o output/square.o
bob gcc -c hello.c -o output/hello.o

bob gcc output/hello.o output/square.o -o output/hello

