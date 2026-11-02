#!/bin/bash
set -e
cd "$(dirname "$0")"
rm -rf out && mkdir -p out
javac -d out src/*.java
