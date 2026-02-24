# Livepaper Architecture (Draft)

## Processes

1. `LiveSceneApp` (menu bar control plane)
- edits config
- starts/stops worker
- shows health/errors

2. `LiveSceneWorker` (wallpaper playback plane)
- owns AV playback + display windows
- no settings UI
- emits metrics/status

3. `Livepaper.saver` (screen saver module)
- reads shared config
- uses same playback policy
- degrades gracefully in host restrictions

## Shared core

`LiveSceneCore` (Swift package)
- Config schema + migration
- Playback policy (battery/thermal/load)
- Video catalog scan and validation
- Shared model types

## IPC

- Primary: XPC between app and worker
- No anonymous global notification commands
- Command set: start/stop/reloadConfig/status

## Storage

- `~/Library/Application Support/LiveScene/config.json`
- atomic write via temp + rename
- schema versioned

## Safety defaults

- startup disabled until valid source exists
- bounded retry for worker crash
- disable audio by default
- explicit user opt-in for login startup
