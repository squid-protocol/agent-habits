#!/bin/sh
# Builds ./solver from solver.c. Run from anywhere; exits non-zero on failure.
set -e
cd "$(dirname "$0")"
gcc -std=c17 -O2 -Wall -Wextra -pedantic -o solver solver.c
