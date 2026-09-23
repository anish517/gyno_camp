#!/usr/bin/env bash
# Builds on this machine and installs on omway-internal, bypassing CI. Needs the
# pinned SDK (~/fvm/versions/3.47.1) and the omway-internal ssh alias (root).
#   deploy/omway-internal/deploy-from-mac.sh            # API + web
#   SKIP_WEB=1 deploy/omway-internal/deploy-from-mac.sh # API only
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SDK=${SDK:-$HOME/fvm/versions/3.47.1/bin}
export FLUTTER=${FLUTTER:-$SDK/flutter} DART=${DART:-$SDK/dart}

OUT=$(mktemp -d -t gynocamp-dist)
trap 'rm -rf "$OUT"' EXIT
bash "$HERE/build.sh" "$OUT"

echo "== upload $(du -sh "$OUT" | cut -f1) and install"
COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs -C "$OUT" -czf - . | ssh omway-internal \
    'set -e; D=$(mktemp -d /tmp/gynocamp-dist.XXXXXX); trap "rm -rf $D" EXIT; tar xzf - -C "$D"; bash /srv/gynocamp/deploy/install.sh "$D"'
