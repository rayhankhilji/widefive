#!/usr/bin/env bash
# Packs build/widefive.app into dist/widefive-<version>.dmg (drag-to-Applications window with a
# drawn background) and dist/widefive-<version>.zip (what Sparkle and Homebrew download).
# Uses only hdiutil + Finder AppleScript; the Finder layout step is best-effort so headless CI never fails on it.
source "$(dirname "$0")/common.sh"

[[ -d "$APP_PATH" ]] || die "build the app first: Scripts/build-app.sh"
VERSION="$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)"
VOLNAME="$APP_NAME"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"
mkdir -p "$DIST_DIR"
rm -f "$DMG" "$ZIP"

step "Zipping"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP"

step "Staging DMG"
TMP="$(mktemp -d)"; trap 'hdiutil detach "$MNT" -force >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT
STAGE="$TMP/stage"; mkdir -p "$STAGE/.background"
ditto "$APP_PATH" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
swift "$ROOT/Scripts/art.swift" dmg "$TMP/bg.png" 1
swift "$ROOT/Scripts/art.swift" dmg "$TMP/bg@2x.png" 2
tiffutil -cathidpicheck "$TMP/bg.png" "$TMP/bg@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null 2>&1
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

RW="$TMP/rw.dmg"
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ -format UDRW -size "${SIZE_MB}m" "$RW"
MNT="$(hdiutil attach "$RW" -readwrite -noverify -noautoopen -nobrowse | awk -F'\t' '/\/Volumes\// {print $NF; exit}')"
[[ -d "$MNT" ]] || die "could not mount $RW"
command -v SetFile >/dev/null && SetFile -a C "$MNT" || true

step "Laying out the Finder window"
DISK="$(basename "$MNT")"
if ! with_timeout 60 osascript <<OSA >/dev/null 2>&1; then warn "Finder layout skipped (no GUI session?) — DMG still works"; fi
tell application "Finder"
  tell disk "$DISK"
    open
    set w to container window
    set current view of w to icon view
    set toolbar visible of w to false
    set statusbar visible of w to false
    set bounds of w to {200, 120, 860, 568}
    set o to icon view options of w
    set arrangement of o to not arranged
    set icon size of o to 112
    set text size of o to 13
    set background picture of o to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of w to {170, 222}
    set position of item "Applications" of w to {490, 222}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
sync
hdiutil detach "$MNT" -quiet || hdiutil detach "$MNT" -force -quiet
MNT=""

step "Compressing"
hdiutil convert -quiet "$RW" -format ULFO -o "$DMG"
IDENTITY="$(signing_identity)"
if [[ "$IDENTITY" != "-" ]]; then codesign --force --sign "$IDENTITY" --timestamp "$DMG"; fi

bold "✓ $DMG ($(du -h "$DMG" | cut -f1))"
bold "✓ $ZIP ($(du -h "$ZIP" | cut -f1))"
