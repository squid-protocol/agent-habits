#!/bin/sh
cd "$(dirname "$0")" && chmod +x engine && python3 -m py_compile engine.py
