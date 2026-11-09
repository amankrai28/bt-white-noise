#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/BT White Noise.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc "$ROOT/src/BTWhiteNoise.swift" -o "$APP/Contents/MacOS/BTWhiteNoise" -framework AppKit -framework CoreAudio
cp "$ROOT/resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
printf 'Built %s (not launched)\n' "$APP"
