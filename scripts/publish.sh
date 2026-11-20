#!/bin/sh
# Rebuild the feed and commit dist/ so the HTTPS raw URLs update.
# Run from a cron/systemd timer or by hand; CI uses the same target.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

[ -f keys/private/unregdb.sec ] || {
    echo "missing keys/private/unregdb.sec (see scripts/gen-keys.sh)" >&2
    exit 1
}
[ -f keys/private/unregdb-apk.key ] || {
    echo "missing keys/private/unregdb-apk.key" >&2
    exit 1
}

VERSION="${VERSION:-9999.0001-r1}" sh scripts/build-feed.sh

git add dist
if git diff --cached --quiet; then
    echo "feed unchanged"
    exit 0
fi
git commit -m "chore(feed): rebuild $(date -u +%Y-%m-%dT%H:%MZ)"
git push origin HEAD
