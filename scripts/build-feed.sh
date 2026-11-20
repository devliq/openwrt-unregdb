#!/bin/sh
# Build the repository indexes for both package managers.
#   dist/opkg/{Packages,Packages.gz,Packages.sig}
#   dist/apk/{packages.adb,packages.adb.sig,index.json}
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION="${VERSION:-9999.0001-r1}"
PKGNAME=wireless-regdb
USIGN_KEY="${USIGN_KEY:-$ROOT/keys/private/unregdb.sec}"
APK_SIGN_KEY="${APK_SIGN_KEY:-$ROOT/keys/private/unregdb-apk.key}"
ARCH="${ARCH_PACKAGES:-all}"

"$ROOT/scripts/build-packages.sh"

USIGN=$("$ROOT/scripts/build-usign.sh")
APK=$("$ROOT/scripts/build-apk-tool.sh")

IPK="$ROOT/dist/opkg/${PKGNAME}_${VERSION}_all.ipk"
APKFILE="$ROOT/dist/apk/${PKGNAME}-${VERSION}.apk"

# ------------------------------------------------------------------ opkg feed
SIZE=$(wc -c < "$IPK" | tr -d ' ')
SHA=$(sha256sum "$IPK" | awk '{print $1}')
cat > "$ROOT/dist/opkg/Packages" <<EOF
Package: $PKGNAME
Version: $VERSION
Depends: libc
Filename: $(basename "$IPK")
Size: $SIZE
SHA256sum: $SHA
Section: firmware
Architecture: all
Maintainer: devliq <devliq@users.noreply.github.com>
Installed-Size: 1088
Description: Unrestricted wireless regulatory database
EOF
gzip -9 -c "$ROOT/dist/opkg/Packages" > "$ROOT/dist/opkg/Packages.gz"
[ -f "$USIGN_KEY" ] || { echo "missing usign key: $USIGN_KEY" >&2; exit 1; }
"$USIGN" -S -s "$USIGN_KEY" -m "$ROOT/dist/opkg/Packages" -x "$ROOT/dist/opkg/Packages.sig"

# ------------------------------------------------------------------- apk feed
mkdir -p "$ROOT/dist/apk"
# OpenWrt publishes an UNSIGNED packages.adb (the detached .sig is usign).
# apk trusts unsigned indexes only over HTTPS; signing the index itself makes
# apk reject it unless every client trusts that key.
"$APK" mkndx --root / --allow-untrusted \
    --output "$ROOT/dist/apk/packages.adb" "$APKFILE"
printf '{"version":2,"architecture":"%s","packages":{"%s":"%s"}}\n' \
    "$ARCH" "$PKGNAME" "$VERSION" > "$ROOT/dist/apk/index.json"

# Public keys + checksums.
mkdir -p "$ROOT/dist/keys"
cp "$ROOT/keys/unregdb.pub" "$ROOT/keys/unregdb-apk.pem" "$ROOT/dist/keys/"
( cd "$ROOT/dist" && sha256sum \
    regulatory.db \
    keys/unregdb.pub keys/unregdb-apk.pem \
    opkg/Packages opkg/Packages.gz opkg/Packages.sig \
    "opkg/$(basename "$IPK")" \
    apk/packages.adb apk/index.json \
    "apk/$(basename "$APKFILE")" > SHA256SUMS )

echo "feed built in $ROOT/dist"
