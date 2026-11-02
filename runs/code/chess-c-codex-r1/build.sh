#!/bin/sh
set -eu
cd "$(dirname "$0")"
gcc -std=c17 -O3 -Wall -Wextra -pedantic engine.c -o engine
