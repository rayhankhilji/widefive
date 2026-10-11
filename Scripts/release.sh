#!/usr/bin/env bash
# Full release, runnable on any Mac (and what .github/workflows/release.yml runs):
#   Scripts/release.sh v0.2.0             build app → notarize (optional) → dmg + zip → appcast → cask, into dist/
#   Scripts/release.sh v0.2.0 --publish   …then create the GitHub release with gh (needs `gh auth login` or GH_TOKEN)
source "$(dirname "$0")/common.sh"
TAG="${1:?usage: release.sh vX.Y.Z [--publish]}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || die "tag must look like v1.2.3"
PUBLISH=0; [[ "${2:-}" == "--publish" ]] && PUBLISH=1
export WIDEFIVE_VERSION="${TAG#v}"
VERSION="$WIDEFIVE_VERSION"

[[ -n "$(sparkle_public_key)" ]] || die "No Sparkle public key. Run Scripts/setup-sparkle-keys.sh once and commit Resources/sparkle-public-key.txt"
rm -rf "$DIST_DIR"; mkdir -p "$DIST_DIR"

"$ROOT/Scripts/build-app.sh"
"$ROOT/Scripts/notarize.sh" "$APP_PATH"
"$ROOT/Scripts/make-dmg.sh"
"$ROOT/Scripts/notarize.sh" "$DIST_DIR/$APP_NAME-$VERSION.dmg"
"$ROOT/Scripts/appcast.sh" "$TAG"

step "Homebrew cask"
SHA="$(shasum -a 256 "$DIST_DIR/$APP_NAME-$VERSION.zip" | cut -d' ' -f1)"
sed -E -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 .*/  sha256 \"$SHA\"/" \
  "$ROOT/Casks/widefive.rb" > "$DIST_DIR/widefive.rb"
(cd "$DIST_DIR" && shasum -a 256 "$APP_NAME-$VERSION.dmg" "$APP_NAME-$VERSION.zip" > SHA256SUMS.txt)

ls -lh "$DIST_DIR"
if (( PUBLISH )); then
  step "Publishing GitHub release $TAG"
  command -v gh >/dev/null || die "gh not installed"
  gh release create "$TAG" --repo "$REPO_SLUG" --title "widefive $VERSION" --generate-notes --verify-tag \
    "$DIST_DIR/$APP_NAME-$VERSION.dmg" "$DIST_DIR/$APP_NAME-$VERSION.zip" "$DIST_DIR/appcast.xml" \
    "$DIST_DIR/SHA256SUMS.txt" "$DIST_DIR/widefive.rb"
  bold "✓ https://github.com/$REPO_SLUG/releases/tag/$TAG"
  echo "Homebrew: copy dist/widefive.rb to rayhankhilji/homebrew-tap/Casks/widefive.rb and push."
else
  bold "Dry run done. Publish with: Scripts/release.sh $TAG --publish  (after pushing the tag)"
fi
