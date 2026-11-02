#!/bin/sh
# Build the COBOL chess engine (GnuCOBOL 3.1). Produces ./engine.
set -e
cd "$(dirname "$0")"
cobc -x -free -I src -O2 -o engine src/engine.cob src/core.cob src/search.cob src/input.cob
