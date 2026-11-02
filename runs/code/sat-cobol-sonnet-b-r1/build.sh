#!/bin/bash
cd "$(dirname "$0")"
cobc -x -O2 -free -fnotrunc -o solver solver.cob
