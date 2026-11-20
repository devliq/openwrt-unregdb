#!/bin/sh
# Build the OpenWrt usign tool (signify-compatible) into .cache/.
# Prints the path to the binary.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CACHE="$ROOT/.cache"
SRC="$CACHE/usign"
BIN="$SRC/build/usign"

if [ -x "$BIN" ]; then
    echo "$BIN"
    exit 0
fi

mkdir -p "$CACHE"
git clone -q --depth 1 https://git.openwrt.org/project/usign.git "$SRC" 2>/dev/null || \
    git clone -q --depth 1 https://github.com/openwrt/usign.git "$SRC"
mkdir -p "$SRC/build"
(cd "$SRC/build" && cmake .. -DCMAKE_BUILD_TYPE=Release >/dev/null && make -j"$(nproc)" >/dev/null)
echo "$BIN"
