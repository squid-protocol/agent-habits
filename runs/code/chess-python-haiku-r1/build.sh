#!/bin/sh
# Builds PyChess from a clean checkout: checks that the sources compile and makes the launcher executable.
set -eu
cd "$(dirname "$0")"
python3 -m py_compile engine
chmod +x engine
rm -rf __pycache__
echo "build ok"
