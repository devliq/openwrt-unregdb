#!/bin/sh
# Build the host "apk" tool (apk-tools) with mkpkg/mkndx support.
# Prints the path to the binary. Cached under .cache/.
set -eu

VER="${APK_TOOLS_VERSION:-v3.0.5}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CACHE="$ROOT/.cache"
SRC="$CACHE/apk-tools-$VER"
BIN="$SRC/build/src/apk"

if [ -x "$BIN" ]; then
    echo "$BIN"
    exit 0
fi

mkdir -p "$CACHE"
if [ ! -d "$SRC" ]; then
    git clone -q --depth 1 --branch "$VER" https://github.com/alpinelinux/apk-tools.git "$SRC"
fi

if ! command -v meson >/dev/null 2>&1; then
    python3 -m venv "$CACHE/venv" >/dev/null 2>&1 || true
    "$CACHE/venv/bin/pip" -q install meson
    PATH="$CACHE/venv/bin:$PATH"
    export PATH
fi

(cd "$SRC" && meson setup build --prefix="$CACHE/apk-prefix" -Ddocs=disabled >/dev/null && ninja -C build >/dev/null)
echo "$BIN"
