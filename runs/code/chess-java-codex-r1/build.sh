#!/bin/sh
set -eu
cd "$(dirname "$0")"
rm -rf out
mkdir -p out
javac --release 17 -encoding UTF-8 -d out Main.java
