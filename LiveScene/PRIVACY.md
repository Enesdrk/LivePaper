# Privacy

## What Livepaper Stores Locally
- `~/Library/Application Support/LiveScene/config.json`
  - source folder path
  - selected wallpaper/screen saver media paths
  - display assignments
  - local preferences (`startAtLogin`, `muteAudio`, `scaleMode`, `userPaused`, `optimizeForEfficiency`, `privacyModeEnabled`)
- `~/Library/Application Support/LiveScene/worker-status.json`
  - current runtime state, pid, performance metrics (cpu/memory/rate), timestamps

## Data Transmission
- The project does not send analytics/telemetry or media metadata to external servers.
- No account login/cloud sync is implemented.

## Logs
- Privacy mode is enabled by default (`privacyModeEnabled: true`).
- In privacy mode, diagnostics avoid detailed path disclosure and favor concise error summaries.

## User Controls
- To reset all local state:
  - `./scripts/reset_local_state.sh`
- To disable privacy mode manually:
  - set `"privacyModeEnabled": false` in `config.json`
