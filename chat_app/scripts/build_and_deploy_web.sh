#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-/data2/chat_project/flutter_sdk/flutter/bin/flutter}"
RELEASES_DIR="${PMCHAT_WEB_RELEASES_DIR:-$APP_DIR/releases}"

cd "$APP_DIR"
"$FLUTTER_BIN" build web --release --wasm --no-web-resources-cdn \
  --dart-define=API_BASE_URL=https://gateway.chat.pm2550.com \
  --dart-define=WS_BASE_URL=wss://gateway.chat.pm2550.com

BUILD_ID="$($FLUTTER_BIN pub run tool/generate_web_release_manifest.dart build/web | tail -n 1)"
test -n "$BUILD_ID"
test -f "build/web/pmchat_build_manifest.json"
test -f "build/web/main.dart.js"
test -f "build/web/main.dart.wasm"
test -f "build/web/main.dart.mjs"
test -f "build/web/canvaskit/canvaskit.wasm"

mkdir -p "$RELEASES_DIR"
TEMP_RELEASE="$RELEASES_DIR/.${BUILD_ID}.staging"
FINAL_RELEASE="$RELEASES_DIR/$BUILD_ID"
if [[ -e "$FINAL_RELEASE" ]]; then
  if [[ ! -f "$FINAL_RELEASE/.last_build_id" ]] ||
    [[ "$(tr -d '\n' < "$FINAL_RELEASE/.last_build_id")" != "$BUILD_ID" ]]; then
    echo "Existing release is incomplete or has the wrong build id: $FINAL_RELEASE" >&2
    exit 3
  fi
  echo "Verified existing immutable release: $FINAL_RELEASE"
else
  mkdir "$TEMP_RELEASE"
  cp -a build/web/. "$TEMP_RELEASE/"
  mv "$TEMP_RELEASE" "$FINAL_RELEASE"
fi

if [[ -L "$RELEASES_DIR/current" ]]; then
  CURRENT_TARGET="$(readlink -f "$RELEASES_DIR/current")"
  ln -sfn "$CURRENT_TARGET" "$RELEASES_DIR/.previous.new"
  mv -Tf "$RELEASES_DIR/.previous.new" "$RELEASES_DIR/previous"
fi
ln -s "$FINAL_RELEASE" "$RELEASES_DIR/.current.new"
mv -Tf "$RELEASES_DIR/.current.new" "$RELEASES_DIR/current"

echo "PM chat web release activated: $BUILD_ID"
echo "Current: $(readlink -f "$RELEASES_DIR/current")"
if [[ -L "$RELEASES_DIR/previous" ]]; then
  echo "Previous: $(readlink -f "$RELEASES_DIR/previous")"
fi
