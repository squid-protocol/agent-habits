#!/bin/sh
set -eu
cd "$(dirname "$0")"
gcc -std=c17 -O2 -Wall -Wextra -o solver solver.c
