#!/usr/bin/env bash
# Builds the solver from a clean checkout and places the binary at ./solver.
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release
cp -f target/release/solver ./solver
