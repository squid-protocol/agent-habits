#!/bin/sh
# Builds the engine from a clean checkout: compiles src/*.java with javac (Java 17) into out/.
set -e
cd "$(dirname "$0")"
rm -rf out
mkdir -p out
javac --release 17 -encoding UTF-8 -Xlint:all -d out src/*.java
chmod +x engine
echo "build ok"
