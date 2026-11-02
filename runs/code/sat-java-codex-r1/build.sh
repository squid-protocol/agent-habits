#!/bin/sh
set -eu
cd "$(dirname "$0")"
rm -f ./*.class
javac --release 17 Main.java
