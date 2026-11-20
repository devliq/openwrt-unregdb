#!/bin/sh
# Install (or revert) an unrestricted cfg80211 regulatory.db on OpenWrt.
#
#   install : back up the current database and install the published one
#   revert  : restore the backup
#   status  : show the current regulatory domain and installed hash
#
# Environment:
#   BASE   base URL of the repository (default: the main branch on GitHub)
#   DEST   target file (default: /lib/firmware/regulatory.db)
#
# A reboot is required for cfg80211 to load the new database.
set -eu

BASE="${BASE:-https://raw.githubusercontent.com/devliq/openwrt-unregdb/main}"
DEST="${DEST:-/lib/firmware/regulatory.db}"
BACKUP="${DEST}.orig"
TMP="/tmp/regulatory.db.new"

usage() {
    cat <<EOF
usage: $0 [install|revert|status]

  install   back up $DEST and replace it with the unrestricted database
  revert    restore the pre-install backup
  status    print the loaded regulatory domain and file hashes

After install or revert, reboot:
  reboot
EOF
}

fetch() {
    # Prefer a local file next to the script; fall back to BASE.
    dir=$(dirname "$0")
    if [ -f "$dir/dist/regulatory.db" ]; then
        cp "$dir/dist/regulatory.db" "$TMP"
    else
        command -v curl >/dev/null 2>&1 || {
            echo "curl is required" >&2
            exit 1
        }
        curl -fsSL "$BASE/dist/regulatory.db" -o "$TMP"
    fi
}

sha() {
    sha256sum "$1" | awk '{print $1}'
}

case "${1:-install}" in
    install)
        [ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
        fetch
        want=$(curl -fsSL "$BASE/dist/SHA256SUMS" 2>/dev/null | awk '{print $1}' | head -1 || true)
        got=$(sha "$TMP")
        if [ -n "${want:-}" ] && [ "$want" != "$got" ]; then
            echo "sha256 mismatch: expected $want, got $got" >&2
            rm -f "$TMP"
            exit 1
        fi
        [ -f "$DEST" ] && [ ! -f "$BACKUP" ] && cp "$DEST" "$BACKUP"
        cp "$TMP" "$DEST"
        chmod 644 "$DEST"
        rm -f "$TMP"
        sync
        echo "installed $DEST (sha256 $got)"
        if [ -f "$BACKUP" ]; then
            echo "original saved as $BACKUP"
        fi
        echo "reboot to load the new regulatory database"
        ;;
    revert)
        [ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
        if [ ! -f "$BACKUP" ]; then
            echo "no backup at $BACKUP" >&2
            exit 1
        fi
        cp "$BACKUP" "$DEST"
        sync
        echo "restored $DEST from $BACKUP; reboot to apply"
        ;;
    status)
        echo "installed: $(sha "$DEST")  $DEST"
        [ -f "$BACKUP" ] && echo "backup:    $(sha "$BACKUP")  $BACKUP"
        echo
        iw reg get 2>/dev/null || true
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
