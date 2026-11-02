#!/usr/bin/env bash
# Builds the engine from a clean tree and places the binary at ./engine.
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release
cp -f target/release/engine ./engine
chmod +x ./engine
