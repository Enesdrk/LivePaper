# Changelog

## [1.0.1] - 2026-07-14

### Added
- Redesigned the application icon and menu bar icon with a custom vector layered screens logo.
- Overhauled the Control Center interface with modern glassmorphism (translucent materials), custom metrics grid, pulsing status animations, and a unified library video layout.
- Integrated window controls (traffic lights) directly into a transparent custom titlebar.

### Fixed
- Fixed video wallpaper disappearing/resetting after macOS sleep/wake cycles by elevating window level and adding workspace power observers.
- Fixed screensaver showing black screens/resetting after waking from sleep due to strict sandbox container paths and AVPlayer state corruptions.

## [1.0.0] - 2026-02-24

Initial public release.

Highlights:
- Live wallpaper + screen saver support in a single project.
- Separate media assignment for wallpaper and screen saver.
- Menu bar app with Control Center.
- Worker stability improvements (safer render/session lifecycle).
- Privacy mode enabled by default (reduced sensitive path details in logs).
- Local installer packaging:
  - `.pkg` installer
  - `.dmg` containing installer
