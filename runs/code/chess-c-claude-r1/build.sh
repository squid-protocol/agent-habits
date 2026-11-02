#!/bin/sh
cd "$(dirname "$0")" && gcc -std=c17 -O2 -o engine engine.c
