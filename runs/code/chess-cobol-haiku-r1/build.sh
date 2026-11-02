#!/bin/sh
# Builds the ./engine UCI executable from engine.cob with GnuCOBOL (cobc).
set -e
cd "$(dirname "$0")"
cobc -x -free -O2 -o engine engine.cob
