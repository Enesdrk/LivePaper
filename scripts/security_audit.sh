#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/4] Checking for network client usage..."
if rg -n "URLSession|NSURLConnection|http://|https://|NWConnection|CFNetwork|Alamofire" Sources >/dev/null; then
  echo "FAIL: network-related APIs found."
  exit 1
fi
echo "PASS"

echo "[2/4] Checking for embedded secrets..."
if rg -n -P "(?i)(api[_-]?key\\s*[:=]|secret\\s*[:=]|authorization\\s*:|bearer\\s+[a-z0-9._-]+)" Sources scripts >/dev/null; then
  echo "FAIL: potential secret patterns found."
  exit 1
fi
echo "PASS"

echo "[3/4] Checking privacy mode references..."
if ! rg -n "privacyModeEnabled" Sources >/dev/null; then
  echo "FAIL: privacyModeEnabled not found in Sources."
  exit 1
fi
echo "PASS"

echo "[4/4] Build + tests..."
swift build >/dev/null
swift test >/dev/null
echo "PASS"

echo "Security audit checks completed successfully."
