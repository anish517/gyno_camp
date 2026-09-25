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

echo "== server: $("$DART" --version 2>&1)"
PKG=$(mktemp -d)
trap 'rm -rf "$PKG"' EXIT
mkdir "$PKG/bin"
cp "$ROOT/deploy/omway-internal/server/pubspec.yaml" "$ROOT/deploy/omway-internal/server/pubspec.lock" "$PKG/"
cp "$ROOT/gyno_camp/bin/server.dart" "$PKG/bin/"
(
    cd "$PKG"
    "$DART" pub get --enforce-lockfile
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
