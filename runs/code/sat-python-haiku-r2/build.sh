#!/bin/sh
# Build step for the SAT solver: the solver is a single standard-library Python 3 script.
# Makes it executable and checks that it is valid Python 3 source.
set -e
cd "$(dirname "$0")"
chmod +x solver
python3 -c 'import sys; compile(open("solver", encoding="utf-8").read(), "solver", "exec")'
echo "build ok"
