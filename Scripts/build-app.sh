#!/usr/bin/env bash
# Builds build/widefive.app: universal release binary + Sparkle.framework + Info.plist + icon, signed.
#   Scripts/build-app.sh            universal (arm64 + x86_64)
#   Scripts/build-app.sh --native   this Mac's architecture only (faster, for local testing)
# Env: WIDEFIVE_VERSION, WIDEFIVE_BUILD, CODESIGN_IDENTITY ("-" = ad-hoc), SPARKLE_PUBLIC_KEY, SPARKLE_FEED_URL
source "$(dirname "$0")/common.sh"

ARCH_FLAGS=(--arch arm64 --arch x86_64)
[[ "${1:-}" == "--native" ]] && ARCH_FLAGS=()

VERSION="$(app_version)"
BUILD="$(app_build)"
IDENTITY="$(signing_identity)"
PUBKEY="$(sparkle_public_key)"
bold "widefive $VERSION ($BUILD)"

step "Compiling release binary ${ARCH_FLAGS[*]:-(native)}"
cd "$ROOT"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
[[ -x "$BIN_DIR/$APP_NAME" ]] || die "no binary at $BIN_DIR/$APP_NAME"

step "Assembling $APP_NAME.app"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$APP_PATH/Contents/Frameworks"
cp "$BIN_DIR/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"
ditto "$BIN_DIR/Sparkle.framework" "$APP_PATH/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_PATH/Contents/MacOS/$APP_NAME" 2>/dev/null || true

PLIST="$APP_PATH/Contents/Info.plist"
sed -e "s|__VERSION__|$VERSION|" -e "s|__BUILD__|$BUILD|" -e "s|__FEED_URL__|$FEED_URL|" \
    -e "s|__SPARKLE_PUBLIC_KEY__|$PUBKEY|" "$ROOT/Resources/Info.plist" > "$PLIST"
if [[ -z "$PUBKEY" ]]; then
  /usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$PLIST"
  warn "No Sparkle public key (run Scripts/setup-sparkle-keys.sh once) — this build won't auto-update."
fi
plutil -lint -s "$PLIST"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

ICNS="$ROOT/Resources/AppIcon.icns"
[[ -f "$ICNS" ]] || "$ROOT/Scripts/make-icon.sh"
cp "$ICNS" "$APP_PATH/Contents/Resources/AppIcon.icns"

step "Signing ($([[ "$IDENTITY" == "-" ]] && echo "ad-hoc" || echo "$IDENTITY"))"
SIGN=(codesign --force --sign "$IDENTITY")
# Hardened runtime + timestamp only with a real identity: ad-hoc code has no Team ID, so library
# validation would refuse to load Sparkle.framework under the hardened runtime.
[[ "$IDENTITY" != "-" ]] && SIGN+=(--options runtime --timestamp) || SIGN+=(--timestamp=none)
FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$FW/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$FW/Versions/B/Autoupdate"
"${SIGN[@]}" "$FW/Versions/B/Updater.app"
"${SIGN[@]}" "$FW"
# Ad-hoc code is otherwise identified by its hash, so every update looked like a new app to macOS and silently lost
# its Accessibility / Automation permissions. Pin the designated requirement to the bundle id so grants carry over.
APP_SIGN=("${SIGN[@]}")
if [[ "$IDENTITY" == "-" ]]; then
  APP_SIGN+=(--requirements "=designated => identifier \"$BUNDLE_ID\"")
fi
"${APP_SIGN[@]}" --entitlements "$ROOT/Resources/widefive.entitlements" "$APP_PATH"
if [[ "$IDENTITY" == "-" ]]; then
  DR="$(codesign -d -r- "$APP_PATH" 2>&1 || true)"
  [[ "$DR" == *"designated => identifier \"$BUNDLE_ID\""* ]] || die "designated requirement not pinned to $BUNDLE_ID: $DR"
fi
codesign --verify --deep --strict "$APP_PATH"

bold "✓ $APP_PATH  ($(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME"), $(du -sh "$APP_PATH" | cut -f1))"
