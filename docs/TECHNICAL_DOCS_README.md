# Technical Docs

This file contains developer/technical details that are intentionally kept out of the main README.

## Installer Artifacts
- DMG (distribution):
  - `dist/Livepaper-Local-<version>.dmg`
- PKG (inside DMG):
  - `dist/Livepaper-Local-<version>.pkg`

## Build From Source
```bash
swift build
swift test
swift run LiveSceneApp
```

## Packaging Commands
```bash
./scripts/package_local_release.sh
./scripts/package_local_dmg.sh
```

## Local Files
- Config:
  - `~/Library/Application Support/LiveScene/config.json`
- Worker status:
  - `~/Library/Application Support/LiveScene/worker-status.json`

## Security and Privacy
- Privacy: [PRIVACY.md](PRIVACY.md)
- Security: [SECURITY.md](SECURITY.md)
- Quick audit:
  - `./scripts/security_audit.sh`

## Contributor Docs
- Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)
- Changelog: [CHANGELOG.md](CHANGELOG.md)
