#!/usr/bin/env bash
# Builds on this machine and installs on a GynoCamp server, bypassing CI. Needs the
# pinned SDK (~/fvm/versions/3.47.1) and root ssh access to the target.
#   deploy/omway-internal/deploy-from-mac.sh            # dev: API + web
#   SKIP_WEB=1 deploy/omway-internal/deploy-from-mac.sh # dev: API only
#   DEPLOY_HOST=root@213.163.200.92 CENTRAL_SERVER_URL=http://213.163.200.92 \
#     deploy/omway-internal/deploy-from-mac.sh          # production
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SDK=${SDK:-$HOME/fvm/versions/3.47.1/bin}
export FLUTTER=${FLUTTER:-$SDK/flutter} DART=${DART:-$SDK/dart}
HOST=${DEPLOY_HOST:-omway-internal}

OUT=$(mktemp -d -t gynocamp-dist)
trap 'rm -rf "$OUT"' EXIT
bash "$HERE/build.sh" "$OUT"

echo "== upload $(du -sh "$OUT" | cut -f1) and install"
COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs -C "$OUT" -czf - . | ssh "$HOST" \
    'set -e; D=$(mktemp -d /tmp/gynocamp-dist.XXXXXX); trap "rm -rf $D" EXIT; tar xzf - -C "$D"; bash /srv/gynocamp/deploy/install.sh "$D"'
