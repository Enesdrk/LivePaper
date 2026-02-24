# Security Policy

## Scope
- Project: Livepaper (`LiveSceneApp`, `LiveSceneWorker`, `LiveSceneSaver`, `LiveSceneCore`)
- Distribution: local unsigned builds (`.pkg`, `.dmg`) unless you add your own signing/notarization pipeline

## Security Baseline
- No outbound telemetry/networking is implemented in app/worker/saver code paths.
- No embedded API keys or service tokens are used.
- Worker process management is restricted to exact process name matching (`pgrep -x LiveSceneWorker`).
- Config/status are written only under user-local app support directory:
  - `~/Library/Application Support/LiveScene/config.json`
  - `~/Library/Application Support/LiveScene/worker-status.json`
- Privacy mode is enabled by default (`privacyModeEnabled: true`) and reduces path detail in diagnostics.

## Threat Model (Practical)
- This app reads local video paths and plays them on wallpaper/screen saver surfaces.
- Sensitive risk is mainly local metadata exposure (file paths in logs/config), not remote exfiltration.
- If your device is shared, file paths in local config remain visible to local users with account access.

## Recommended Hardening Before Broad Distribution
1. Code signing with a Developer ID certificate.
2. Apple notarization for installer artifacts.
3. Add CI checks for:
   - forbidden network APIs
   - forbidden secrets in repository
   - build reproducibility
4. Add release checksums/signature verification instructions for users.

## Reporting
- Open a GitHub issue with label `security`.
- Include:
  - affected component
  - reproduction steps
  - expected/actual behavior
  - impact assessment
