#!/usr/bin/env bash
# Builds the GynoCamp deploy artifacts into <out-dir>:
#   <out>/gynocamp_server   Linux x86-64 binary of gyno_camp/bin/server.dart
#   <out>/web/              Flutter web bundle          (skipped with SKIP_WEB=1)
#   <out>/BUILD_SHA         commit the artifacts were built from
#
# Used by the CI build job and by deploy-from-mac.sh. Needs Flutter >= 3.47
# (Dart 3.13); override the binaries with FLUTTER=... / DART=...
#
# CENTRAL_SERVER_URL and GEMINI_API_KEY are compiled into the web bundle, so
# anyone who loads the site can read them. Use a dev Gemini key restricted to
# this domain.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${1:?usage: build.sh <out-dir>}
mkdir -p "$OUT" && OUT=$(cd "$OUT" && pwd)
URL=${CENTRAL_SERVER_URL:-https://gynocamp.omwaytechnologies.com}
FLUTTER=${FLUTTER:-flutter}
DART=${DART:-dart}

# The server is compiled as a standalone package: `dart compile exe` refuses the
# app's pubspec (Flutter plugins with native build hooks: sqlite3, objective_c).
# Its pubspec is generated here from whatever gyno_camp/bin/*.dart imports, each
# package pinned to the version in gyno_camp/pubspec.lock, so adding an import
# to the server needs no change to this script.
APP="$ROOT/gyno_camp"
echo "== server: $("$DART" --version 2>&1)"
PKG=$(mktemp -d)
trap 'rm -rf "$PKG"' EXIT
mkdir "$PKG/bin"
cp "$APP"/bin/*.dart "$PKG/bin/"
SDK=$(awk '/^environment:/{f=1;next} f&&/^  sdk:/{print $2;exit}' "$APP/pubspec.yaml" | tr -d "'\"")
{
    printf 'name: gynocamp_server\npublish_to: none\nenvironment:\n  sdk: "%s"\ndependencies:\n' "$SDK"
    for p in $(grep -hoE "^import ['\"]package:[a-z0-9_]+/" "$APP"/bin/*.dart | sed -E "s/^import ['\"]package://; s#/##" | sort -u); do
        v=$(awk -v p="  $p:" '$0==p{f=1;next} f&&/^  [a-z0-9_]+:$/{exit} f&&/^    version:/{gsub(/"/,"",$2);print $2;exit}' "$APP/pubspec.lock")
        [[ -n $v ]] || { echo "build: gyno_camp/bin imports package:$p, which is not in gyno_camp/pubspec.lock; add it to gyno_camp/pubspec.yaml" >&2; exit 1; }
        echo "  $p: $v"
    done
} > "$PKG/pubspec.yaml"
sed 's/^/   /' "$PKG/pubspec.yaml"
(
    cd "$PKG"
    "$DART" pub get
    "$DART" compile exe bin/server.dart --target-os=linux --target-arch=x64 -o "$OUT/gynocamp_server"
)

if [[ ${SKIP_WEB:-0} != 1 ]]; then
    echo "== web: $("$FLUTTER" --version 2>/dev/null | head -1)  CENTRAL_SERVER_URL=$URL"
    cd "$ROOT/gyno_camp"
    "$FLUTTER" pub get
    args=(--release --no-wasm-dry-run "--dart-define=CENTRAL_SERVER_URL=$URL")
    [[ -n ${GEMINI_API_KEY:-} ]] && args+=("--dart-define=GEMINI_API_KEY=$GEMINI_API_KEY")
    "$FLUTTER" build web "${args[@]}"
    rm -rf "$OUT/web"
    cp -R build/web "$OUT/web"
fi

git -C "$ROOT" rev-parse HEAD > "$OUT/BUILD_SHA"
echo "== built $(cat "$OUT/BUILD_SHA") into $OUT"
ls -la "$OUT"
