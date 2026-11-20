#!/bin/sh
# Build both package formats into dist/:
#   dist/opkg/wireless-regdb_<ver>_all.ipk
#   dist/apk/wireless-regdb-<ver>.apk
# Requires: python3, tar, ar, gzip, openssl, and root/unshare -r/fakeroot.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION="${VERSION:-9999.0001-r1}"
PKGNAME=wireless-regdb
APK_SIGN_KEY="${APK_SIGN_KEY:-$ROOT/keys/private/unregdb-apk.key}"

mkdir -p "$ROOT/dist/opkg" "$ROOT/dist/apk"
python3 "$ROOT/build.py" -o "$ROOT/dist/regulatory.db"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- opkg (.ipk)
mkdir -p "$WORK/ipk/control" "$WORK/ipk/data/lib/firmware"
install -m 0644 "$ROOT/dist/regulatory.db" "$WORK/ipk/data/lib/firmware/regulatory.db"
cat > "$WORK/ipk/control/control" <<EOF
Package: $PKGNAME
Version: $VERSION
Depends: libc
Section: firmware
Architecture: all
Maintainer: devliq <devliq@users.noreply.github.com>
Installed-Size: 1088
Description: Unrestricted wireless regulatory database
EOF
(cd "$WORK/ipk/control" && tar --owner=0 --group=0 --numeric-owner --mtime=@0 \
    -czf "$WORK/ipk/control.tar.gz" .)
(cd "$WORK/ipk/data" && tar --owner=0 --group=0 --numeric-owner --mtime=@0 \
    -czf "$WORK/ipk/data.tar.gz" .)
printf '2.0\n' > "$WORK/ipk/debian-binary"
( cd "$WORK/ipk" && ar rcs "$ROOT/dist/opkg/${PKGNAME}_${VERSION}_all.ipk" \
    debian-binary control.tar.gz data.tar.gz )

# ---------------------------------------------------------------- apk (.apk)
APK=$( "$ROOT/scripts/build-apk-tool.sh" )
[ -f "$APK_SIGN_KEY" ] || { echo "missing signing key: $APK_SIGN_KEY" >&2; exit 1; }

mkdir -p "$WORK/apk/lib/firmware"
install -m 0644 "$ROOT/dist/regulatory.db" "$WORK/apk/lib/firmware/regulatory.db"
chmod 0755 "$WORK/apk" "$WORK/apk/lib" "$WORK/apk/lib/firmware"

# mkpkg records filesystem ownership; run with a fake root.
cat > "$WORK/mk-apk.sh" <<EOF
#!/bin/sh
set -eu
SOURCE_DATE_EPOCH=0 "$APK" mkpkg \\
    --info "name:$PKGNAME" \\
    --info "version:$VERSION" \\
    --info "description:Unrestricted wireless regulatory database" \\
    --info "arch:noarch" \\
    --info "license:MIT" \\
    --info "origin:feeds/base/firmware/wireless-regdb-unreg" \\
    --info "url:https://github.com/devliq/openwrt-unregdb" \\
    --info "maintainer:devliq <devliq@users.noreply.github.com>" \\
    --sign "$APK_SIGN_KEY" \\
    --files "$WORK/apk" \\
    --output "$ROOT/dist/apk/${PKGNAME}-${VERSION}.apk"
EOF
chmod +x "$WORK/mk-apk.sh"

if [ "$(id -u)" = 0 ]; then
    chown -R 0:0 "$WORK/apk"
    "$WORK/mk-apk.sh"
elif command -v unshare >/dev/null 2>&1 && unshare -r true >/dev/null 2>&1; then
    unshare -r sh -c "chown -R 0:0 '$WORK/apk' && '$WORK/mk-apk.sh'"
elif command -v fakeroot >/dev/null 2>&1; then
    fakeroot sh -c "chown -R 0:0 '$WORK/apk' && '$WORK/mk-apk.sh'"
else
    echo "need root, unshare -r or fakeroot to build the apk" >&2
    exit 1
fi

echo "built:"
ls -l "$ROOT/dist/opkg/${PKGNAME}_${VERSION}_all.ipk" "$ROOT/dist/apk/${PKGNAME}-${VERSION}.apk"
