# Changelog

All notable changes to Ainkrad are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
