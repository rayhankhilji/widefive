#!/usr/bin/env bash
# Notarizes and staples a .app, .dmg or .zip when Apple credentials are present; no-op otherwise.
#   Scripts/notarize.sh build/widefive.app
# Env: APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD (app-specific password) + a Developer ID identity.
source "$(dirname "$0")/common.sh"
TARGET="${1:?usage: notarize.sh <path>}"
if ! can_notarize; then
  warn "Skipping notarization of $(basename "$TARGET") (no Developer ID / APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD)"
  exit 0
fi
step "Notarizing $(basename "$TARGET")"
SUBMIT="$TARGET"
if [[ "$TARGET" == *.app ]]; then
  SUBMIT="$(mktemp -d)/$(basename "$TARGET" .app).zip"
  ditto -c -k --keepParent "$TARGET" "$SUBMIT"
fi
xcrun notarytool submit "$SUBMIT" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" --wait --timeout 30m
[[ "$TARGET" == *.zip ]] || xcrun stapler staple "$TARGET"
