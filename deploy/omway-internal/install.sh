#!/usr/bin/env bash
# Installs build artifacts (from build.sh) on omway-internal. Run as root:
#   install.sh <artifact-dir>
# Installs whichever of gynocamp_server and web/ the directory contains. Each is
# swapped in atomically and the previous version kept as *.prev, so a rollback is
#   mv /srv/gynocamp/bin/gynocamp_server{.prev,} && systemctl restart gynocamp-api
#   rm -rf /srv/gynocamp/www && mv /srv/gynocamp/www{.prev,}
# Ends with a smoke test that fails the deploy if the API is not backed by
# PostgreSQL: server.dart silently falls back to an in-memory store otherwise.
set -euo pipefail

SRC=${1:?usage: install.sh <artifact-dir>}
APP=/srv/gynocamp
DOMAIN=gynocamp.omwaytechnologies.com

die() { echo "install: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root"
SRC=$(realpath -e -- "$SRC") || die "artifact dir does not exist"
[[ -f $SRC/gynocamp_server || -f $SRC/web/index.html ]] || die "no gynocamp_server or web/ in $SRC"
SHA=$(cat "$SRC/BUILD_SHA" 2>/dev/null || echo unknown)

if [[ -f $SRC/gynocamp_server ]]; then
    file -b "$SRC/gynocamp_server" | grep -q 'ELF 64-bit.*x86-64' || die "gynocamp_server is not a Linux x86-64 binary"
    echo "== install API binary"
    install -m 755 -o root -g root "$SRC/gynocamp_server" "$APP/bin/gynocamp_server.next"
    [[ -f $APP/bin/gynocamp_server ]] && cp -p "$APP/bin/gynocamp_server" "$APP/bin/gynocamp_server.prev"
    mv "$APP/bin/gynocamp_server.next" "$APP/bin/gynocamp_server"
    systemctl restart gynocamp-api
fi

if [[ -f $SRC/web/index.html ]]; then
    [[ -f $SRC/web/main.dart.js ]] || die "$SRC/web is not a Flutter web build"
    grep -q "$DOMAIN" "$SRC/web/main.dart.js" || die "web bundle does not reference $DOMAIN (built without CENTRAL_SERVER_URL?)"
    echo "== install web bundle"
    rm -rf "$APP/www.next"
    rsync -a --chown=root:root --chmod=D755,F644 "$SRC/web/" "$APP/www.next/"
    rm -rf "$APP/www.prev"
    [[ -d $APP/www ]] && mv "$APP/www" "$APP/www.prev"
    mv "$APP/www.next" "$APP/www"
    du -sh "$APP/www" | cut -f1 | sed 's/^/   size: /'
fi

echo "== smoke test"
ok=0
for _ in $(seq 1 15); do
    if body=$(curl -fsS http://127.0.0.1:8080/health 2>/dev/null) && grep -q '"postgres_connected":true' <<<"$body"; then
        ok=1; break
    fi
    sleep 1
done
[[ $ok == 1 ]] || { journalctl -u gynocamp-api -n 30 --no-pager; die "API is down or not connected to PostgreSQL"; }
echo "   local  /health -> $body"
curl -fsS -o /dev/null -w "   public /       -> HTTP %{http_code}\n" "https://$DOMAIN/"
curl -fsS -o /dev/null -w "   public /health -> HTTP %{http_code}\n" "https://$DOMAIN/health"

echo "$SHA" > "$APP/DEPLOYED_SHA"
echo "== deployed $SHA OK"
