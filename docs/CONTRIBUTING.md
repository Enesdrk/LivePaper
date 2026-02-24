# Contributing

Thanks for contributing to LivePaper.

## Development Setup
1. Use macOS 13+.
2. From repository root:
   - `swift build`
   - `swift test`
3. Run app:
   - `swift run LivePaperApp`

## Before Opening a PR
1. Keep changes focused and small.
2. Run:
   - `swift build`
   - `swift test`
   - `./scripts/security_audit.sh`
3. Update docs if behavior changes (`README.md`, `SECURITY.md`, `PRIVACY.md`).

## Privacy and Security Requirements
1. Do not add telemetry or external network calls without explicit discussion.
2. Do not commit API keys, tokens, certificates, or private credentials.
3. Keep `privacyModeEnabled` behavior intact or improve it.
4. Prefer privacy-safe logs (no full user path leakage by default).

## Commit and PR Guidance
1. Use clear commit messages describing user-visible impact.
2. Include reproduction steps and validation steps in PR description.
3. If you touch installer scripts, provide resulting artifact names and test notes.
