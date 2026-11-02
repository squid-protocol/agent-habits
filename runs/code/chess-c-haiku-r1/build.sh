#!/bin/sh
# Builds the chess engine: ./engine speaks UCI on stdin/stdout.
set -e
cd "$(dirname "$0")"
CC=${CC:-gcc}
$CC -std=c17 -O2 -Wall -Wextra -pthread -o engine src/board.c src/movegen.c src/eval.c src/search.c src/uci.c
