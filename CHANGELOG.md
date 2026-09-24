# Changelog

All notable changes to Pi Studio are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.0] - 2026-09-25

### Added
- In-app Pi runtime updates from Settings → About. Updates are downloaded with
  the bundled npm runtime, version-checked and smoke-tested, then enabled for
  new sessions while running sessions keep their current runtime.
- Grouped project navigation and a refreshed session sidebar for easier project
  switching.

### Changed
- Refreshed the app shell with a new brand mark, hero empty state, composer,
  session chrome, and transcript presentation.
- Reworked Settings into clearer groups and refreshed project navigation flows.
- Release builds now resolve the npm `latest` Pi package once per workflow run
  and bundle the same version on Windows and Linux.

## [1.0.1] - 2026-09-22

### Added
- Linux x64 build (native GTK header bar, zenity/kdialog folder picker,
  `xdg-open` for reveal-in-folder). Ships as `PiStudio-<version>-Linux-x64.tar.gz`.
- Bundled pi runtime: release builds stage Node 22 plus the pinned
  `@earendil-works/pi-coding-agent` next to the app, so no local `pi` install
  is needed. Override with the `PI_STUDIO_PI` env var.
- Windows installer (`PiStudio-<version>-Setup.exe`) and portable zip alongside
  the release, built by the `Release` workflow on every `v*` tag.
- Providers page for editing `models.json`.

### Changed
- UI re-themed from the reference design and split out of `main.dart` into
  `lib/ui/` (theme tokens, primitives, transcript, review pane, session chrome);
  corner radii unified to 6/8/10.
- GitHub release actions bumped to Node 24 builds.
