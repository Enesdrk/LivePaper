# Livepaper

Livepaper is a macOS app for:
- Live video wallpaper
- Live screen saver

## Supported macOS
- Minimum: macOS 13 (Ventura)
- Recommended: macOS 14+

## Quick Start (Users)
1. Download `Livepaper-Local-<version>.dmg` from Releases.
2. Open DMG.
3. Run `Livepaper-Local-<version>.pkg`.
4. Open `Livepaper` from `/Applications`.
5. In Control Center:
   - Select source folder
   - Choose `Set as Live Wallpaper`
   - Choose `Set as Screen Saver`
6. Open **System Settings > Screen Saver** and select **Livepaper**.

## Screen Saver Setup
1. Go to **System Settings > Screen Saver**.
2. Select **Livepaper** from list.
3. Trigger preview/lock screen and verify video playback.

If screen saver is black:
1. Ensure source folder contains playable files (`.mp4`, `.mov`, `.m4v`).
2. Re-select screen saver media in Livepaper.
3. Re-select Livepaper in System Settings > Screen Saver.

## Installer Artifacts
- DMG (recommended for distribution):
  - `dist/Livepaper-Local-<version>.dmg`
- PKG (inside DMG):
  - `dist/Livepaper-Local-<version>.pkg`

## Build from Source
```bash
swift build
swift test
swift run LiveSceneApp
```

Create local installer:
```bash
./scripts/package_local_release.sh
./scripts/package_local_dmg.sh
```

## Local Files
- Config:
  - `~/Library/Application Support/LiveScene/config.json`
- Worker status:
  - `~/Library/Application Support/LiveScene/worker-status.json`

Reset local state:
```bash
./scripts/reset_local_state.sh
```

## Security and Privacy
- No telemetry or external analytics is implemented.
- Media and settings remain local.
- `privacyModeEnabled` is true by default.
- Run quick audit:
  - `./scripts/security_audit.sh`

## Documentation
- [User Guide](docs/USER_GUIDE.md)
- [Release Notes v1.0.0](docs/RELEASE_1.0.0.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Roadmap](docs/ROADMAP.md)
- [Security](SECURITY.md)
- [Privacy](PRIVACY.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)
- [License](LICENSE)
