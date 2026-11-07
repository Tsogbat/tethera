#!/bin/bash
# Compiles scripts/render_icon.swift together with the app's 3D model and runs it.
# Usage: scripts/render_icon.sh icon | preview <out.png> | shot <out.png>
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="${TMPDIR:-/tmp}/tethera-render-icon"
swiftc -O -parse-as-library -o "$BIN" scripts/render_icon.swift Tethera/Views/Retro/RetroComputer.swift
"$BIN" "$@"
