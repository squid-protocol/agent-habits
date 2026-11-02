#!/bin/sh
# Builds the SAT solver from a clean checkout: compiles src/*.java into build/classes.
set -e
cd "$(dirname "$0")"
rm -rf build
mkdir -p build/classes
javac --release 17 -encoding UTF-8 -Xlint:all -d build/classes src/*.java
