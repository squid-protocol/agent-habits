#!/bin/sh
chmod +x solver
python3 -m py_compile sat.py 2>/dev/null; exit 0
