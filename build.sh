#!/bin/sh
if [ "$1" = release ]; then
  nim c --nimcache:nimcache/build.nim --verbosity:0 -d:release -r build
else
  nim c --nimcache:nimcache/build.nim --verbosity:0 -r build
fi

