#!/bin/sh
cd "$(dirname "$0")" && gcc -std=c17 -O2 -D_POSIX_C_SOURCE=200809L -o engine engine.c
