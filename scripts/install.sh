#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if (( $# != 1 )) || [[ "$1" != *:output ]] || [[ "$1" == *[^a-zA-Z0-9:._-]* ]]; then
  echo 'Usage: scripts/install.sh "YOUR-DEVICE-UID:output"' >&2
  echo 'List devices: mpv --no-config --audio-device=help' >&2
  exit 2
fi
for tool in mpv socat ffmpeg; do command -v "$tool" >/dev/null || { echo "Missing: $tool" >&2; exit 1; }; done
APP="$HOME/Applications/BT White Noise.app"
[[ ! -e "$APP" ]] || { echo 'App already exists. Back it up or remove it before reinstalling.' >&2; exit 1; }
"$ROOT/scripts/build.sh"
mkdir -p "$HOME/Applications" "$HOME/bin" "$HOME/.config/bt-white-noise"
printf '%s\n' "$1" > "$HOME/.config/bt-white-noise/device-uid"
cp "$ROOT/scripts/bt-white-noise" "$HOME/bin/bt-white-noise"
chmod +x "$HOME/bin/bt-white-noise"
AUDIO="$HOME/Library/Application Support/BT White Noise"
mkdir -p "$AUDIO"
for color in white pink brown; do
 [[ -e "$AUDIO/$color.wav" ]] || ffmpeg -v error -f lavfi -i "anoisesrc=color=$color:sample_rate=48000:amplitude=0.2:duration=300:seed=42" -ac 1 -c:a pcm_s24le "$AUDIO/$color.wav"
done
cp -R "$ROOT/build/BT White Noise.app" "$APP"
echo "Installed. Open $APP manually when ready. No playback or login service was started."
