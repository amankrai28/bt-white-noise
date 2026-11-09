# BT White Noise

A native macOS menu-bar and Dock controller for continuous white, pink, and brown noise on a dedicated Bluetooth speaker. The noise engine uses an explicitly selected CoreAudio device while normal application and system audio remain on the Mac's built-in speakers.

## Features

- Swift/AppKit controls with play/stop, sound selection, and real hardware volume.
- Independent `mpv` engine: closing the control window does not stop audio.
- Polling that keeps ordinary Mac audio away from the dedicated speaker while noise is playing.
- Optional built-in microphone selection to avoid Bluetooth headset-mode quality loss.
- Optional launch-at-login/restart support through launchd.
- Local generation of five-minute, 48 kHz, 24-bit mono noise files; no downloads or bundled recordings.

## Requirements

macOS with Xcode Command Line Tools, Homebrew `mpv`, `socat`, and `ffmpeg`, plus a paired Bluetooth speaker. This version assumes built-in speaker/microphone UIDs and a speaker exposing volume on channels 1 and 2. Some devices need adaptation. Tested compilation on an Apple Silicon Mac, not a broad macOS/device matrix.

```
brew install mpv socat ffmpeg
mpv --no-config --audio-device=help
```

Copy your speaker's device UID without the `coreaudio/` prefix. Then:

```
./scripts/install.sh 'YOUR-DEVICE-UID:output'
open "$HOME/Applications/BT White Noise.app"
```

The installer builds and ad-hoc signs the app, generates audio locally, and installs the helper. It does not launch the app, start playback, or enable a login service. It refuses to overwrite an existing BT White Noise app. The UID is stored locally at `~/.config/bt-white-noise/device-uid`; do not commit that file. Restart the controller after changing it.

Select a sound and start at a low volume. Initial remembered volume defaults to 10%; the application is not a sound-level meter, volume percentages are not calibrated decibels, and this is not a medical device. Confirm actual volume and device routing before relying on unattended playback.

### Audio routing behavior

Starting noise explicitly sets normal/system output to the built-in speakers. While noise plays, the controller repairs routing drift. The microphone option changes the input only when the selected speaker's corresponding input device is active. Stopping noise ends enforcement but does not restore prior default audio devices. The helper fails rather than intentionally falling back to the default device if its dedicated device is unavailable. Hardware disconnect/reconnect behavior still depends on macOS and mpv and should be verified with your speaker.

Do not run another controller targeting the same hardware simultaneously: controllers can compete over volume and routing.

### Optional login service

```
./scripts/enable-login.sh
```

This creates and loads a per-user KeepAlive LaunchAgent and starts the controller. Playback is not intentionally started by installation. Once enabled, launchd restarts the controller if it exits. To disable it, quit the controller, unload and remove its LaunchAgent (if it restarts, unload first):

```
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.btnoise.whitenoise.controller.plist"
rm "$HOME/Library/LaunchAgents/local.btnoise.whitenoise.controller.plist"
```

To stop the independent engine: `~/bin/bt-white-noise shutdown`. Removing the app alone does not stop the engine or remove generated audio/configuration.

## Build and test without changing playback

```
./scripts/build.sh
python3 -m unittest discover -s tests -v
```

The build writes only `build/` and does not run the application. Automated tests check shell syntax, bundle metadata, absence of machine identifiers, and helper state/error handling in an isolated temporary home. They do not simulate CoreAudio or certify uninterrupted playback. Live speaker, routing, volume, reconnect, microphone, and login-service testing remains manual and may interrupt audio. Perform those checks when interruption is acceptable.

## Source layout

- `src/BTWhiteNoise.swift`: native controller and CoreAudio routing/volume logic.
- `scripts/bt-white-noise`: mpv IPC helper.
- `scripts/build.sh`, `install.sh`, `enable-login.sh`: packaging and optional setup.
- `resources/Info.plist`: application bundle metadata.
- `tests/test_source.py`: non-disruptive checks.

This is a generalized, privacy-cleaned version of a personal Mac utility. Personal device identifiers, local usernames, playback state, binaries, logs, and recordings are excluded. Generated noise uses FFmpeg's standard noise source; files are not claimed to be clinically validated or perfectly seamless loops.

MIT licensed. See LICENSE.
