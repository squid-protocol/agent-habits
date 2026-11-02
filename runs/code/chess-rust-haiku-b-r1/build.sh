#!/usr/bin/env bash
# Builds the engine and places the binary at ./engine.
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release
cp target/release/chess ./engine
chmod +x ./engine
