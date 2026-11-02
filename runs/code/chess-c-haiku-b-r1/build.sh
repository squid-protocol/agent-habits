#!/bin/sh
# Builds the UCI chess engine into ./engine. Exits 0 on success.
set -eu
cd "$(dirname "$0")"
CC="${CC:-gcc}"
CFLAGS="-std=c17 -O2 -Wall -Wextra -Wno-unused-parameter"
$CC $CFLAGS -o engine src/board.c src/search.c src/uci.c -pthread
