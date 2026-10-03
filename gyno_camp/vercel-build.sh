#!/bin/bash
set -e

echo "=== Installing Flutter SDK ==="
if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
fi

export PATH="$PATH:$HOME/flutter/bin"

echo "=== Flutter Version ==="
flutter --version

echo "=== Getting Dependencies ==="
flutter pub get

echo "=== Building Flutter Web Release ==="
BUILD_ARGS="--release --no-wasm-dry-run"
if [ -n "$CENTRAL_SERVER_URL" ]; then
  echo "Injecting CENTRAL_SERVER_URL=$CENTRAL_SERVER_URL"
  BUILD_ARGS="$BUILD_ARGS --dart-define=CENTRAL_SERVER_URL=$CENTRAL_SERVER_URL"
fi

flutter build web $BUILD_ARGS

echo "=== Flutter Web Build Complete ==="
