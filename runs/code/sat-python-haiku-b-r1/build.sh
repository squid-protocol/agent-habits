#!/usr/bin/env bash
# The solver is a single standard-library Python 3 script, so the build only needs to
# make it executable and check that it parses.
set -euo pipefail
cd "$(dirname "$0")"
chmod +x solver
python3 -c 'import ast; ast.parse(open("solver").read())'
