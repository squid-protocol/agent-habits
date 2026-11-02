#!/bin/sh
# Builds the engine from a clean checkout and places the binary at ./engine.
set -eu
cd "$(dirname "$0")"
cargo build --release --quiet
cp target/release/engine ./engine
chmod +x ./engine
