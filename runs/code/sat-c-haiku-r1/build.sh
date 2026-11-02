#!/bin/sh
# Builds the SAT solver: ./solver (from solver.c).
set -e
cd "$(dirname "$0")"
gcc -std=c17 -O2 -Wall -Wextra -Wpedantic -o solver solver.c
