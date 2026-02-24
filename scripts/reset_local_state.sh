#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT_DIR="$HOME/Library/Application Support/LivePaper"
CONFIG_PATH="$APP_SUPPORT_DIR/config.json"
STATUS_PATH="$APP_SUPPORT_DIR/worker-status.json"
COMMAND_PATH="$APP_SUPPORT_DIR/worker-command.json"
MEDIA_DIR="$APP_SUPPORT_DIR/Media"
USER_SAVER_MEDIA="$HOME/Library/Screen Savers/LivePaper.saver/Contents/Resources/preferred_compat.mp4"

echo "[1/4] Stopping running LivePaper processes..."
if command -v pgrep >/dev/null 2>&1; then
  pids="$(pgrep -x LivePaperApp || true)"
  if [[ -n "${pids:-}" ]]; then
    while IFS= read -r pid; do
      kill "$pid" 2>/dev/null || true
    done <<< "$pids"
  fi

  pids="$(pgrep -x LivePaperWorker || true)"
  if [[ -n "${pids:-}" ]]; then
    while IFS= read -r pid; do
      kill "$pid" 2>/dev/null || true
    done <<< "$pids"
  fi
fi

echo "[2/4] Resetting app support files..."
mkdir -p "$APP_SUPPORT_DIR"
rm -f "$STATUS_PATH" "$COMMAND_PATH"
rm -rf "$MEDIA_DIR"
mkdir -p "$MEDIA_DIR"

cat > "$CONFIG_PATH" <<'JSON'
{
  "displayAssignments": [],
  "muteAudio": true,
  "optimizeForEfficiency": true,
  "privacyModeEnabled": true,
  "scaleMode": "fill",
  "schemaVersion": 1,
  "screenSaverSelectedVideoPath": null,
  "selectedVideoPath": null,
  "sourceFolder": "",
  "startAtLogin": false,
  "userPaused": false,
  "wallpaperSelectedVideoPath": null
}
JSON

echo "[3/4] Clearing user saver staged media..."
rm -f "$USER_SAVER_MEDIA"

echo "[4/4] Done."
echo "Config: $CONFIG_PATH"
echo "Media : $MEDIA_DIR"
