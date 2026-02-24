# Livepaper User Guide

## Supported macOS Versions
- Minimum supported: macOS 13 (Ventura)
- Recommended: macOS 14+ for better stability and media decode behavior

## What Livepaper Provides
- Live video wallpaper (desktop background playback)
- Live screen saver playback
- Separate wallpaper and screen saver media selection
- Menu bar app + Control Center for runtime control

## Install (DMG)
1. Download `Livepaper-Local-<version>.dmg` from Releases.
2. Open the DMG.
3. Double-click `Livepaper-Local-<version>.pkg`.
4. Finish installer steps.
5. Open `Livepaper` from `/Applications`.

## First Run Setup
1. Open `Livepaper` (Control Center opens).
2. In Source section, select a folder containing `.mp4`, `.mov`, or `.m4v`.
3. In Library, choose media:
   - `Set as Live Wallpaper`
   - `Set as Screen Saver`
4. Verify playback starts.

## Screen Saver Setup (Important)
1. Open **System Settings > Screen Saver**.
2. Select **Livepaper** as the active screen saver.
3. Set wait time and optional hot corner.
4. Lock screen or preview screen saver to verify playback.

Notes:
- Livepaper uses shared local config at:
  - `~/Library/Application Support/LiveScene/config.json`
- If screen saver shows black screen:
  - ensure source folder has playable videos
  - re-select screen saver video in Livepaper
  - re-open System Settings > Screen Saver and reselect Livepaper

## Common Operations
- Pause/Resume playback from Control Center.
- Toggle efficiency mode if CPU/thermal pressure is high.
- Restart worker from menu if playback desync occurs.
- Reset local state:
  - `./scripts/reset_local_state.sh`

## Uninstall
```bash
pkill -x Livepaper 2>/dev/null || true
pkill -x LiveSceneApp 2>/dev/null || true
pkill -x LiveSceneWorker 2>/dev/null || true
sudo rm -rf /Applications/Livepaper.app
sudo rm -rf "/Library/Screen Savers/Livepaper.saver"
rm -rf "$HOME/Library/Screen Savers/Livepaper.saver"
```

## Privacy
- No telemetry/external analytics implemented.
- Data remains local.
- `privacyModeEnabled` is enabled by default.
