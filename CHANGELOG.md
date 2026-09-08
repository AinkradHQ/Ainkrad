# Changelog

All notable changes to Ainkrad are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.19.0] — 2026-09-08

### Fixed

- **The app could not be opened.** `AVKit.framework` was never linked — the code
  used SwiftUI's `VideoPlayer` and `AVPlayer` but touched no AVKit ObjC symbol,
  so autolinking pulled in only the `_AVKit_SwiftUI` shim, whose
  `VideoPlayerView` subclasses AVKit's `AVPlayerView`. The first `VideoPlayer`
  ever built aborted the process, and macOS state restoration then replayed the
  same window on every launch. Now linked explicitly and guarded by a test.
- **A new `AVPlayer` on every frame.** Media cards built their player inside
  `body`, so every hover and drag frame allocated a player, a player item and a
  CoreMedia connection. A card now owns its player for its lifetime. Fixed in
  Scry and in the Sage timeline's inline video views.
- **The chosen app icon reverted on quit.** Only the running process's Dock tile
  was being set, so the Finder fell back to the shipped icon. The choice is now
  stamped on the bundle.
- Generated media whose file has been removed now shows the unavailable
  placeholder instead of being handed to a player.

### Changed

- **Launching no longer resumes the last session.** Workspaces you never named
  are dropped, the active workspace is forced to main, and pane contents return
  only when the new Settings → General → "Restore layout on launch" is enabled
  (default off).
- **Scry is auto-arranged.** Cards flow newest-first into content-sized columns
  instead of stacking at one point. Dragging or resizing a card pins it where
  you put it and the flow re-packs around it.
- Scry cards live in memory for the session, capped at 50, evicting oldest-first
  and never evicting a pinned card. They no longer persist to disk.
- Audio cards get a real transport — play/pause driven by actual player state,
  an elapsed readout and a working scrubber — instead of a video surface
  squashed to 44pt.

### Removed

- **`scry_render` no longer accepts `x`, `y`, `width`, `height` or `z`.** These
  asked a language model for five numbers it had no basis for choosing, so it
  omitted them and every card fell back to one default rect. Replaced by a
  single optional `size` hint (`small` / `medium` / `large` / `full`); the app
  owns placement.
- The unused transcript-replay path and the on-disk `agent-canvas` document.

## [0.1.0] — 2026-07-04

First MVP release.

### Added

- **Floating-island HUD workspace** — panes tile in a balanced grid over one
  shared, blurred island; translucent panes reveal the same backdrop.
- **Tiling window management** — split right/down, drag title bars to rearrange,
  drag seams to resize, duplicate, and close. Views move rather than recreate,
  so a dragged terminal keeps its running session.
- **Built-in Terminal** (forked, no-reflow SwiftTerm) — color schemes,
  transparency, fonts, cursor styles, and scrollback. The title bar adopts the
  terminal's own color and opacity, so each pane reads as one continuous window.
- **Focus Mode** — zoom one pane to fill the canvas, with scale-pop transitions
  and resize-free pane switching.
- **Workspaces** — multiple named workspaces, a visual overview, direct jumps,
  wrap-around cycling, and on-disk layout persistence.
- **Command launcher** (fuzzy match), HUD-styled **Settings**, and seven themes:
  Neon Blue, Cyber Purple, Dracula, Nord, Tokyo Night, Gruvbox, Solarized Dark.
- **Release pipeline** — `scripts/release.sh` (build → sign → notarize → staple
  → publish) and a CI workflow that runs it on `v*` tags.

### Fixed

- Terminal output no longer duplicates on resize, drag-rearrange, or Focus
  toggles (animated frame changes are coalesced to one settled resize).
- No stray `zsh` `%` when opening several terminals in quick succession (the
  shell now spawns already sized to its pane).

[Unreleased]: https://github.com/AinkradHQ/Ainkrad/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/AinkradHQ/Ainkrad/releases/tag/v0.1.0
