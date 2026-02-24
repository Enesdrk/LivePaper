# Livepaper Roadmap

## Phase 0: Core Foundation (now)
- [x] Comparative audit
- [x] Core package scaffold
- [ ] Config persistence + schema migration
- [ ] Policy engine (battery/thermal/load)
- [ ] Catalog scan with filtering and deterministic sorting

## Phase 1: Wallpaper MVP
- [x] Worker process with one display playback
- [x] Menu app controls: select folder/video, start/stop
- [ ] Health panel (current video, fps, cpu hint, errors)

## Phase 2: Multi-display + stability
- [x] Per-display assignment
- [x] Space/screen change rebind
- [x] Worker render failure backoff

## Phase 3: Screensaver integration
- [x] `.saver` bridge target using shared config
- [x] Host failure auto-retry fallback
- [x] Shared source selection between wallpaper and screensaver
- [x] Packaging/install scripts for local `.saver` deployment

## Phase 4: Hardening
- [ ] Integration tests for config + policy
- [ ] Fault injection tests (missing file, invalid codec, display changes)
- [ ] Log redaction and diagnostics export
- [x] Start at login toggle with SMAppService sync
