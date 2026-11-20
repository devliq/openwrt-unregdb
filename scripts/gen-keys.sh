#!/bin/sh
# Generate the two signing keypairs:
#   keys/unregdb.pub          usign public key (opkg Packages + apk index .sig)
#   keys/private/unregdb.sec  usign secret key   (never commit)
#   keys/unregdb-apk.pem      EC P-256 public key (apk package signatures)
#   keys/private/unregdb-apk.key  EC private key (never commit)
#
# Back up keys/private/ outside the repository (OpenBao
# kv/network/unregdb) and set the same values as GitHub Actions secrets:
#   USIGN_SECRET_B64, APK_SIGN_KEY_B64
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/keys/private"
[ -f "$ROOT/keys/unregdb.pub" ] && { echo "keys already exist in $ROOT/keys" >&2; exit 1; }

USIGN=$("$ROOT/scripts/build-usign.sh")
"$USIGN" -G -p "$ROOT/keys/unregdb.pub" -s "$ROOT/keys/private/unregdb.sec" \
    -c "devliq openwrt-unregdb feed key"

openssl ecparam -name prime256v1 -genkey -noout -out "$ROOT/keys/private/unregdb-apk.key"
openssl ec -in "$ROOT/keys/private/unregdb-apk.key" -pubout -out "$ROOT/keys/unregdb-apk.pem" 2>/dev/null

chmod 600 "$ROOT/keys/private/"*
echo "generated:"
ls -l "$ROOT/keys" "$ROOT/keys/private"
echo
echo "usign public key fingerprint: $("$USIGN" -F -p "$ROOT/keys/unregdb.pub")"
