#!/bin/sh
# Builds ./solver from solver.cob with GnuCOBOL. Exits non-zero on failure.
set -e
cd "$(dirname "$0")"
cobc -x -free -O2 -o solver solver.cob
