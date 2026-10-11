# Shared helpers for the packaging scripts. Source it, don't run it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="widefive"
BUNDLE_ID="com.rayhankhilji.widefive"
REPO_SLUG="rayhankhilji/widefive"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
FEED_URL="${SPARKLE_FEED_URL:-https://github.com/$REPO_SLUG/releases/latest/download/appcast.xml}"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
PUBLIC_KEY_FILE="$ROOT/Resources/sparkle-public-key.txt"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
step() { printf '\033[1;35m▸\033[0m \033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# Version: $WIDEFIVE_VERSION, else an exact vX.Y.Z tag on HEAD, else the VERSION file.
app_version() {
  if [[ -n "${WIDEFIVE_VERSION:-}" ]]; then echo "${WIDEFIVE_VERSION#v}"; return; fi
  local tag
  if tag="$(git -C "$ROOT" describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null)"; then echo "${tag#v}"; return; fi
  tr -d ' \n' < "$ROOT/VERSION"
}

# Build number (CFBundleVersion, what Sparkle compares): commit count, always increasing on main.
app_build() {
  if [[ -n "${WIDEFIVE_BUILD:-}" ]]; then echo "$WIDEFIVE_BUILD"; return; fi
  git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1
}

# Public EdDSA key: $SPARKLE_PUBLIC_KEY, else Resources/sparkle-public-key.txt (created by setup-sparkle-keys.sh).
sparkle_public_key() {
  if [[ -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then echo "$SPARKLE_PUBLIC_KEY"; return; fi
  [[ -f "$PUBLIC_KEY_FILE" ]] && tr -d ' \n' < "$PUBLIC_KEY_FILE" || true
}

# "-" (ad-hoc) unless a Developer ID identity is configured or present in the keychain.
signing_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then echo "$CODESIGN_IDENTITY"; return; fi
  local id
  id="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
  echo "${id:--}"
}

can_notarize() {
  [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && "$(signing_identity)" != "-" ]]
}

ensure_sparkle_tools() {
  [[ -x "$SPARKLE_BIN/generate_appcast" ]] || (cd "$ROOT" && swift package resolve >/dev/null)
  [[ -x "$SPARKLE_BIN/generate_appcast" ]] || die "Sparkle tools not found in $SPARKLE_BIN"
}

# with_timeout <seconds> <cmd...>: stock macOS has no `timeout`; perl's alarm does the job.
with_timeout() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }
