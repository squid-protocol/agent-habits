#!/bin/bash
cd "$(dirname "$0")"
cobc -x -O2 -free -o solver solver.cob
