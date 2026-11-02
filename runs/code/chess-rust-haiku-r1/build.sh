#!/usr/bin/env bash
# Build the chess engine from a clean checkout and place the binary at ./engine.
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release
cp target/release/engine ./engine
chmod +x ./engine
