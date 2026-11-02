#!/bin/sh
cd "$(dirname "$0")" && cargo build --release 2>&1 && exit 0
