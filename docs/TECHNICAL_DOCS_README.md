# Technical Docs

This file contains developer/technical details that are intentionally kept out of the main README.

## Installer Artifacts
- DMG (distribution):
  - `dist/LivePaper-Local-<version>.dmg`
- PKG (inside DMG):
  - `dist/LivePaper-Local-<version>.pkg`

## Build From Source
```bash
swift build
swift test
swift run LivePaperApp
```

## Packaging Commands
```bash
./scripts/package_local_release.sh
./scripts/package_local_dmg.sh
```

## Local Files
- Config:
  - `~/Library/Application Support/LivePaper/config.json`
- Worker status:
  - `~/Library/Application Support/LivePaper/worker-status.json`

## Security and Privacy
- Privacy: [PRIVACY.md](PRIVACY.md)
- Security: [SECURITY.md](SECURITY.md)
- Quick audit:
  - `./scripts/security_audit.sh`

## Contributor Docs
- Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)
- Changelog: [CHANGELOG.md](CHANGELOG.md)
