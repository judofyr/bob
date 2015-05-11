# Bob the Builder

Bob is a project builder inspired by Bill McCloskey's
[memoize.py](https://github.com/kgaughan/memoize.py). The idea is that
you can replace your Makefile with a single shell script:

```sh
#!/bin/sh

eval "`bob --start || echo exit`"

bob mkdir -p output

bob gcc -c square.c -o output/square.o
bob gcc -c hello.c -o output/hello.o

bob gcc output/hello.o output/square.o -o output/hello
```

The first time you run this script Bob will silently figure out the
dependencies for you:

```
output/hello    => output/hello.o output/square.o
output/hello.o  => hello.c square.h
output/square.o => square.c square.h
```

The next time you invoke your build script Bob will instead look at the
modification times and checksums to figure out the minimal set of
commands to build everything correctly (in parallel).

## Current status

Bob is a recently started project is **NOT** ready to be used. Tasks:

-   **Dependency tracker for Mac OS X**: The basics are done (using
    `DYLD_INSERT_LIBRARIES`).

-   **Depenedency tracker for Linux**: I've been playing with syscall
    interception using pthread, but nothing has been committed/pushed yet.

-   **Dependency database**: Next up is building the dependency database from
    the results from the dependency tracking.

-   **Re-builder**: Then I will start looking at the re-builder which will
    look at the dependency database and modification times and construct a
    set of commands to re-build the project.

-   **Cycle detection**: In order to handle LaTeX properly I'm thinking
    about including a cycle detector that will re-run commands until a
    consistent result is achieved. This means that you would just write

    ```sh
    bob pdflatex article
    bob bibtex article
    ```

    and Bob would automatically figure out that it needs re-run pdflatex.

