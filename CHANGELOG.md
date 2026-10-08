# Changelog

All notable changes to **MacExpert** — a native macOS controller for SPE Expert amplifiers
(serial / WebSocket RCU) that also ships as an
[Amateur Radio Suite](https://github.com/VU3ESV/AmateurRadioSuite) plugin. Format follows
[Keep a Changelog](https://keepachangelog.com/); a release is cut on every merge to `main`
(tags `vX.Y.Z`).

## [Unreleased]

### Added
- **Update check against GitHub releases** (standalone app only — the Suite plugin excludes
  it): about 10 s after launch, at most once a day, one anonymous `GET` of
  `api.github.com/repos/vu2cpl/macexpert-spe/releases/latest`; if the tag is newer than
  `CFBundleShortVersionString`, a dialog with the release notes and **Download** (opens the
  release page) / **Skip This Version** / **Remind Me Later**. **MacExpert → Check for
  Updates…** always reports; **Check for updates automatically** (default on) sits beside it.
  `MacExpert/UpdateChecker.swift` is byte-identical across VU2CPL's Swift apps. Nothing is
  downloaded or installed automatically. Refined 2026-10-09: only a successful check (HTTP 200
  with a `tag_name`) stores the time — a failed one (offline, timeout, any HTTP error including
  the 403 rate limit, bad JSON) stores nothing and is retried at the next launch, or after 1 h
  while running; an hourly timer repeats the daily check for as long as the app runs (never
  while one of its dialogs is open); and a development build (version containing "dev", e.g.
  `build-app.sh`'s `0.0.0-dev`) never checks on its own — Check for Updates… still works.
- **CI + Release pipelines** (previously none): CI builds + tests the app and the plugin
  `.appex` on every PR; a GitHub Release is cut on **every merge to `main`** (auto patch-bump
  of the latest `vX.Y.Z` tag) with the universal app `.zip` and the `.radioplugin`. Tag-push
  and manual dispatch also work.
- **Out-of-process plugin** ([CONVERTING-A-PLUGIN.md](https://github.com/VU3ESV/AmateurRadioSuite/blob/main/docs/CONVERTING-A-PLUGIN.md)):
  an ExtensionKit `.appex` (`Xcode/`) + `scripts/make-radioplugin.sh` packaging
  `MacExpert.radioplugin`, so the suite can browse/install MacExpert and host it sandboxed via
  `EXHostViewController`. To avoid restructuring the package, the `.appex` recompiles the app's
  own sources (excluding the standalone `@main` + resources); **the standalone app and
  `Package.swift` are unchanged**.
  - *Deferred:* an in-process `RadioPlugin` adapter (would need a library/exe package split);
    the shipping suite hosts plugins out-of-process, so it isn't needed yet.

## [2.0.1] — 2026-04-30
### Changed
- Move all serial I/O off the main thread to a dedicated `ioQueue`.
### Added
- "Amp Powered Off" banner with a traffic watchdog; allow RCU capture in WebSocket mode.

## [2.0.0] — 2026-04-26
### Added
- Live two-way mirroring of the amplifier display via RCU LCD-frame parsing (serial +
  WebSocket parity), info screens, and a standby banner.
- Fixture-based regression tests for the RCU frame parser (7 screens, 18 tests) and a
  reverse-engineering write-up (`docs/REVERSE_ENGINEERING.md`).
- Universal (arm64 + x86_64) build via `lipo`; full-area alert banner, UI toggles, MID power
  scale; refreshed README.
