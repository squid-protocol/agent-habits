#!/bin/sh
set -eu
cd "$(dirname "$0")"
cargo build --release --offline
cp target/release/engine ./engine
