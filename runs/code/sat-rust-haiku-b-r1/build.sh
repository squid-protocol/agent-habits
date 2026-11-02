#!/bin/sh
# Builds the solver with cargo (release profile) and places the binary at ./solver.
set -eu
cd "$(dirname "$0")"
cargo build --release
cp -f target/release/solver ./solver
