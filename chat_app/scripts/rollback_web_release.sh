#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASES_DIR="${PMCHAT_WEB_RELEASES_DIR:-$APP_DIR/releases}"

if [[ ! -L "$RELEASES_DIR/current" || ! -L "$RELEASES_DIR/previous" ]]; then
  echo "Both current and previous release symlinks are required." >&2
  exit 2
fi

CURRENT_TARGET="$(readlink -f "$RELEASES_DIR/current")"
PREVIOUS_TARGET="$(readlink -f "$RELEASES_DIR/previous")"
ln -s "$PREVIOUS_TARGET" "$RELEASES_DIR/.current.rollback"
mv -Tf "$RELEASES_DIR/.current.rollback" "$RELEASES_DIR/current"
ln -s "$CURRENT_TARGET" "$RELEASES_DIR/.previous.rollback"
mv -Tf "$RELEASES_DIR/.previous.rollback" "$RELEASES_DIR/previous"

echo "Rolled back PM chat web to: $(readlink -f "$RELEASES_DIR/current")"
