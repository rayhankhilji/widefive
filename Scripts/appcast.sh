#!/usr/bin/env bash
# Writes dist/appcast.xml: the previous release's appcast plus the new zip, EdDSA-signed.
#   Scripts/appcast.sh v0.2.0
# Key: $SPARKLE_PRIVATE_KEY (CI secret) or the login keychain entry made by setup-sparkle-keys.sh.
source "$(dirname "$0")/common.sh"
TAG="${1:?usage: appcast.sh vX.Y.Z}"; VERSION="${TAG#v}"
ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"
[[ -f "$ZIP" ]] || die "missing $ZIP (run Scripts/make-dmg.sh)"
ensure_sparkle_tools

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cp "$ZIP" "$WORK/"
# Keep history: start from the appcast of the current latest release, if there is one.
if curl -fsSL "$FEED_URL" -o "$WORK/appcast.xml" 2>/dev/null; then
  step "Updating the published appcast"
else
  rm -f "$WORK/appcast.xml"; step "Creating a new appcast"
fi

# Release notes shown in the update window: commits since the previous tag.
END="$TAG"; git -C "$ROOT" rev-parse -q --verify "$TAG" >/dev/null || END=HEAD
PREV="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v[0-9]*' "$END^" 2>/dev/null || true)"
{
  echo "## widefive $VERSION"
  echo
  git -C "$ROOT" log --no-merges --pretty='- %s' "${PREV:+$PREV..}$END" | head -40
} > "$WORK/$APP_NAME-$VERSION.md"

ARGS=(--download-url-prefix "${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/$REPO_SLUG/releases/download/$TAG/}"
      --link "https://github.com/$REPO_SLUG" --embed-release-notes --maximum-deltas 0)
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" --ed-key-file - "${ARGS[@]}" "$WORK"
else
  "$SPARKLE_BIN/generate_appcast" "${ARGS[@]}" "$WORK"
fi
grep -q 'sparkle:edSignature' "$WORK/appcast.xml" || die "appcast has no EdDSA signature"
cp "$WORK/appcast.xml" "$DIST_DIR/appcast.xml"
bold "✓ $DIST_DIR/appcast.xml"
