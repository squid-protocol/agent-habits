#!/bin/sh
# Builds ./solver (GnuCOBOL 3.1) from solver.cob.
set -e
cd "$(dirname "$0")"
cobc -x -O2 -free -Wall -o solver solver.cob
