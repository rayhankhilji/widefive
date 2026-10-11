#!/usr/bin/env bash
# One-time: create the EdDSA key pair that signs updates.
#  - private key: stays in your login keychain, and is uploaded as the GitHub secret SPARKLE_PRIVATE_KEY
#  - public key:  written to Resources/sparkle-public-key.txt (commit it; it ends up as SUPublicEDKey)
# Never commit the private key. Back it up (e.g. in your password manager): losing it means
# existing installs can't auto-update anymore.
source "$(dirname "$0")/common.sh"
ensure_sparkle_tools

step "Generating (or reusing) the Sparkle key in your login keychain"
"$SPARKLE_BIN/generate_keys" >/dev/null
PUB="$("$SPARKLE_BIN/generate_keys" -p)"
echo "$PUB" > "$PUBLIC_KEY_FILE"
bold "✓ public key → Resources/sparkle-public-key.txt: $PUB"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
"$SPARKLE_BIN/generate_keys" -x "$TMP/sparkle_private_key" >/dev/null
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO_SLUG" < "$TMP/sparkle_private_key"
  bold "✓ uploaded GitHub secret SPARKLE_PRIVATE_KEY"
else
  warn "gh not logged in. Add the secret by hand: GitHub → $REPO_SLUG → Settings → Secrets and variables → Actions"
  warn "  name: SPARKLE_PRIVATE_KEY   value: the output of  $SPARKLE_BIN/generate_keys -x /dev/stdout"
fi
echo
echo "Next: git add Resources/sparkle-public-key.txt && git commit -m 'Add Sparkle public key' && git push"
