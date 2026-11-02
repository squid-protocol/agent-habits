#!/bin/sh
# Build step for the UCI chess engine. The engine is a single Python 3 file (standard library only),
# so "building" means checking that it parses and that it answers the UCI handshake.
set -e
cd "$(dirname "$0")"
chmod +x engine
python3 -c 'import ast, sys; ast.parse(open("engine", encoding="utf-8").read(), "engine")'
printf 'uci\nisready\nquit\n' | ./engine > /tmp/chess-build-smoke.$$ 2>&1
grep -qx 'uciok' /tmp/chess-build-smoke.$$
grep -qx 'readyok' /tmp/chess-build-smoke.$$
rm -f /tmp/chess-build-smoke.$$
echo "build ok"
