#!/bin/zsh
set -euo pipefail
APP="$HOME/Applications/BT White Noise.app"
[[ -d "$APP" ]] || { echo 'Install the app first.' >&2; exit 1; }
mkdir -p "$HOME/Library/LaunchAgents"
/usr/bin/python3 - <<'PY'
import plistlib
from pathlib import Path
home=Path.home()
obj={'Label':'local.btnoise.whitenoise.controller','ProgramArguments':['/usr/bin/open','-W',str(home/'Applications/BT White Noise.app'),'--args','--background'],'RunAtLoad':True,'KeepAlive':True,'ProcessType':'Interactive','StandardOutPath':'/tmp/local.btnoise.whitenoise.controller.log','StandardErrorPath':'/tmp/local.btnoise.whitenoise.controller.err'}
with (home/'Library/LaunchAgents/local.btnoise.whitenoise.controller.plist').open('wb') as f: plistlib.dump(obj,f)
PY
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.btnoise.whitenoise.controller.plist"
