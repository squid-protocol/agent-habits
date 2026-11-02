#!/bin/sh
set -eu
cd "$(dirname "$0")"
cobc -x -free -O2 -o solver solver.cob
