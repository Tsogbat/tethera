#!/bin/bash
# Signs a published release for the in-app updater, from this Mac (the key never leaves it).
#
#   scripts/sign_release.sh v0.6.1 [key-file]     default key: ~/.config/tethera/update-signing.key
#
# Downloads the release's DMG, checks it against the checksum CI published, signs it, and
# uploads Tethera-macOS.dmg.sig. Until the signature is up, the updater doesn't offer the release.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${1:?usage: scripts/sign_release.sh <tag> [key-file]}"
KEY="${2:-$HOME/.config/tethera/update-signing.key}"
REPO="Tsogbat/tethera"
[ -f "$KEY" ] || { echo "No signing key at $KEY" >&2; exit 1; }
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT
gh release download "$TAG" --repo "$REPO" --pattern 'Tethera-macOS.dmg' --pattern 'Tethera-macOS.dmg.sha256' --dir "$WORK"
(cd "$WORK" && shasum -a 256 -c Tethera-macOS.dmg.sha256)
swift scripts/sign_update.swift sign "$WORK/Tethera-macOS.dmg" "$KEY" > "$WORK/Tethera-macOS.dmg.sig"
swift scripts/sign_update.swift verify "$WORK/Tethera-macOS.dmg" "$(cat "$WORK/Tethera-macOS.dmg.sig")" \
    "$(sed -n 's/.*publicKey = "\(.*\)"/\1/p' Tethera/App/Updater.swift)"
gh release upload "$TAG" "$WORK/Tethera-macOS.dmg.sig" --repo "$REPO" --clobber
echo "Signed $TAG"
