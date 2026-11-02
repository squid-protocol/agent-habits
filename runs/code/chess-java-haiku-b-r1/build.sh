#!/bin/sh
# Compiles every Java source under src/ into build/classes (Java 17, standard library only).
set -eu
cd "$(dirname "$0")"
rm -rf build
mkdir -p build/classes
find src -name '*.java' | sort > build/sources.txt
javac --release 17 -encoding UTF-8 -d build/classes @build/sources.txt
