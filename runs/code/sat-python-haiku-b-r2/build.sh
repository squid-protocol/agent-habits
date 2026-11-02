#!/bin/sh
# Build step: the solver is a single Python 3 script (standard library only).
# Make sure it is executable and that it parses under the Python 3 interpreter.
set -e
cd "$(dirname "$0")"
chmod +x solver
python3 -c "import ast, sys; ast.parse(open('solver', encoding='utf-8').read(), 'solver')"
echo "build ok: ./solver"
