#!/bin/bash
set -e
cd "$(dirname "$0")"
mkdir -p out
javac -d out src/*.java
