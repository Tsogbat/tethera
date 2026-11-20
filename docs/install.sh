#!/bin/bash
# Installs Tethera, the terminal for your AI agents:
#
#   curl -fsSL https://tsogbat.github.io/tethera/install.sh | bash
#
# Downloads the latest release, checks it against its published SHA-256, copies Tethera.app
# to /Applications and links the `tethera` command into ~/.local/bin. Running it again updates.
# Your sessions keep running through an update: they live in Tethera's background daemon.
#
# TETHERA_INSTALL_DIR and TETHERA_BIN_DIR change where the app and the command go.
set -euo pipefail

REPO="Tsogbat/tethera"
APP_DIR="${TETHERA_INSTALL_DIR:-/Applications}"
BIN_DIR="${TETHERA_BIN_DIR:-$HOME/.local/bin}"
BASE="https://github.com/$REPO/releases/latest/download"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf 'tethera install: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Tethera runs on macOS."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || die "Tethera needs macOS 14 Sonoma or later (this Mac has $(sw_vers -productVersion))."

work="$(mktemp -d)"
cleanup() {
    hdiutil detach -quiet "$work/mnt" >/dev/null 2>&1 || true
    rm -rf "${work:?}"
}
trap cleanup EXIT

say "Downloading Tethera"
curl -fL --progress-bar -o "$work/Tethera-macOS.dmg" "$BASE/Tethera-macOS.dmg"
curl -fsSL -o "$work/Tethera-macOS.dmg.sha256" "$BASE/Tethera-macOS.dmg.sha256"
expected="$(awk '{print $1}' "$work/Tethera-macOS.dmg.sha256")"
actual="$(shasum -a 256 "$work/Tethera-macOS.dmg" | awk '{print $1}')"
[ -n "$expected" ] && [ "$expected" = "$actual" ] || die "the download doesn't match its checksum; nothing was installed."

hdiutil attach -nobrowse -readonly -quiet -mountpoint "$work/mnt" "$work/Tethera-macOS.dmg"
[ -d "$work/mnt/Tethera.app" ] || die "the disk image has no Tethera.app."
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$work/mnt/Tethera.app/Contents/Info.plist")"

target="$APP_DIR/Tethera.app"
was_running=0
running() { [ "$(osascript -e 'application id "com.tethera.app" is running' 2>/dev/null)" = "true" ]; }
if running; then
    # Quitting keeps every session running in the daemon; Tethera reopens right where it was.
    was_running=1
    say "Quitting Tethera to update it (your sessions keep running)"
    osascript -e 'quit app id "com.tethera.app"' >/dev/null 2>&1 || true
    for _ in $(seq 1 50); do running || break; sleep 0.2; done
fi

mkdir -p "$APP_DIR"
staged="$APP_DIR/.Tethera.app.installing"
rm -rf "${staged:?}"
ditto "$work/mnt/Tethera.app" "$staged"
if [ -d "$target" ]; then
    rm -rf "${target:?}"
fi
mv "$staged" "$target"
# curl downloads aren't quarantined; this only matters if an older copy was.
xattr -dr com.apple.quarantine "$target" 2>/dev/null || true

mkdir -p "$BIN_DIR"
ln -sf "$target/Contents/Helpers/tethera" "$BIN_DIR/tethera"

say "Installed Tethera $version in $APP_DIR"
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) printf '    Add %s to your PATH to use the tethera command.\n' "$BIN_DIR" ;;
esac
if [ "$was_running" = 1 ] || [ -t 1 ]; then
    open "$target"
fi
