#!/bin/sh
# Build step for the SAT solver. The solver is a pure-Python program (standard library only),
# so "building" means checking the interpreter is present, the source parses, and the entry point is executable.
set -e
cd "$(dirname "$0")"
command -v python3 >/dev/null 2>&1 || { echo "build.sh: python3 not found" >&2; exit 1; }
python3 -c 'import ast, sys; ast.parse(open("solver", encoding="utf-8").read(), "solver")'
chmod +x solver
echo "build.sh: solver ready"
