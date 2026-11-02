#!/bin/sh
# Builds the SAT solver from a clean checkout. Output goes to build/ (not tracked).
set -e
cd "$(dirname "$0")"
rm -rf build
mkdir -p build
javac -encoding UTF-8 -d build src/*.java
chmod +x solver
echo "build ok"
