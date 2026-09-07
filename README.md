<div align="center">

# Ainkrad

**A native macOS AI Agentic Operation System & WorkSpace.**

A Jarvis-inspired, floating-island HUD for macOS: tiled panes over a single blurred
island, a built-in terminal, a distraction-free Focus Mode, and a fully themeable
neon interface.

[![Release](https://img.shields.io/github/v/release/AinkradHQ/Ainkrad?sort=semver)](https://github.com/AinkradHQ/Ainkrad/releases)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-Proprietary-lightgrey)

</div>

---

## Overview

Ainkrad is a workspace shell that treats every tool as a floating panel in a
heads-up display. Panels tile in a balanced grid, share one blurred "island"
backdrop so translucent windows read as a single environment, and can be
rearranged by dragging their title bars. The long-term vision is an **AI agentic
operating layer**; this release delivers the workspace foundation it will run on.

## Features

- **Floating-island HUD workspace** — panes tile in a balanced grid over one
  shared, blurred island; translucent panels reveal the same backdrop so the
  whole space reads as one surface.
- **Tiling window management** — split (right/down), drag a title bar over
  another pane to rearrange, drag the seams to resize, duplicate, and close.
  Structural changes move live views rather than recreating them, so a dragged
  terminal keeps its running session.
- **Built-in Terminal** — a PTY-backed login shell (forked
  [SwiftTerm](https://github.com/AhmedMElhalaby/SwiftTerm)) with configurable
  color schemes, transparency, fonts, cursor styles, and scrollback. The title
  bar adopts the terminal's own color and opacity, so each pane reads as one
  continuous window.
- **Focus Mode** — zoom one pane to fill the canvas with a compact switcher
  rail; smooth scale-pop transitions and resize-free pane switching.
- **Workspaces** — multiple named workspaces with a visual overview, direct
  jumps, wrap-around cycling, and on-disk persistence of your layout.
- **Command launcher** — fuzzy-matched app launcher (⌘K).
- **Themeable** — seven full themes driving both the UI and the terminal's
  Match-Theme palette: **Neon Blue** (default), **Cyber Purple**, **Dracula**,
  **Nord**, **Tokyo Night**, **Gruvbox**, and **Solarized Dark**. Two selectable
  app icons.
- **Extensible built-in-app system** — apps conform to a small `BuiltInApp`
  protocol and register once; the Terminal and Settings ship as built-in apps.

## Requirements

- macOS **14.0+** (runtime deployment target)
- **Xcode-beta** with the macOS 27 SDK — the project currently builds against the
  beta toolchain
- [**XcodeGen**](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- Swift **6.0**

## Build from source

```bash
git clone https://github.com/AinkradHQ/Ainkrad.git
cd Ainkrad

brew install xcodegen          # one-time, if you don't have it
make open                      # generates the Xcode project and opens it (⌘R)

# …or straight from the command line:
make build                     # build (Debug)
make test                      # run the test suite
make help                      # list all targets
```

> The Xcode project is **generated** from `project.yml` by XcodeGen and is *not*
> committed — `project.yml` is the source of truth. `make` regenerates it for
> you; re-run `make generate` after editing `project.yml`. The project currently
> needs the macOS 27 beta SDK, so the `make` targets default `DEVELOPER_DIR` to
> Xcode-beta (override with `make build DEVELOPER_DIR=…` if yours lives
> elsewhere).

## Install a release

**Homebrew (recommended):**

```bash
brew install --cask ahmedmelhalaby/tap/ainkrad
```

One command, and the app launches. Read the caveats it prints — they explain
what you are trusting.

**Or download directly** from the
[**Releases**](https://github.com/AinkradHQ/Ainkrad/releases) page, open the
`.dmg`, and drag **Ainkrad** into Applications. Because the app is not notarized,
macOS will refuse to open it until you clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine "/Applications/Ainkrad.app"
```

(Or allow it in *System Settings → Privacy & Security* after the first blocked
launch.)

### Why it isn't notarized

Notarization requires a paid Apple Developer Program membership. Until that
exists, Ainkrad ships signed with a development certificate but unnotarized, and
two things follow honestly from that:

- macOS quarantines the download. The Homebrew cask clears that flag for you and
  says so; a manual download needs the command above.
- **Plugin code signatures are not verified.** A host that carries no Developer
  ID cannot meaningfully demand one from plugins, so it accepts them and states
  this in the App Store surface rather than pretending otherwise. Plugin
  downloads are still checked against the catalog's SHA-256, so the bytes match
  what was published — what is unverified is *who* published them.

Both tighten automatically the day a Developer ID signature is used: the app
verifies plugin signatures with no code change.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘K` | Open the launcher |
| `⌘1`–`⌘9` | Jump to workspace 1–9 |
| `⌘⌥←` / `⌘⌥→` | Cycle to previous / next workspace |
| `⌥Tab` | Toggle the Workspace Overview |
| `⌘⇧N` | New workspace |
| `⌘←` `⌘→` `⌘↑` `⌘↓` | Move focus between panes |
| `⌘⇧←` `⌘⇧→` `⌘⇧↑` `⌘⇧↓` | Resize the focused pane |
| `⌘M` | Toggle Focus Mode |
| `⌘D` / `⌘⇧D` | Split the focused pane right / down |
| `⌘W` | Close the focused pane |
| `⌘,` | Settings |

## Project structure

```
Ainkrad/
├── project.yml              # XcodeGen project definition (source of truth)
├── Makefile                 # generate · open · build · test · release
├── CHANGELOG.md             # release history
├── Sources/Ainkrad/
│   ├── App/                 # App entry, root view, global keyboard monitor
│   ├── Core/                # Cross-feature foundation
│   │   ├── Launcher/        #   fuzzy app launcher
│   │   ├── Logging/         #   unified logging
│   │   ├── Registry/        #   built-in-app protocol & registry
│   │   ├── Settings/        #   global settings store
│   │   ├── Theming/         #   themes & design tokens
│   │   └── Windowing/       #   tiling layout, panes, seams, workspaces
│   ├── Features/            # Self-contained features (built-in apps)
│   │   ├── Settings/        #   Settings app
│   │   └── Terminal/        #   Terminal app (Models/Services/Settings/Views)
│   └── Resources/           # Assets & bundled fonts
├── Tests/AinkradTests/      # Unit & integration tests
├── scripts/                 # release.sh (build → sign → notarize → publish)
└── .github/workflows/       # CI (release on tag push)
```

## Releasing

`scripts/release.sh` builds a Release `.app`, packages a `.dmg`, and — when
Developer ID credentials are configured — signs (hardened runtime), notarizes,
and staples it. Without credentials it still produces an installable (unsigned)
`.dmg`.

```bash
# Unsigned build (current default):
./scripts/release.sh

# Signed + notarized + published (once you have a Developer ID cert):
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="XXXXXXXXXX"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
VERSION=0.1.1 ./scripts/release.sh --publish
```

`.github/workflows/release.yml` runs the same script on `v*` tag pushes using
repo secrets (dormant until Actions is enabled for the repo).

## Tech stack

Swift 6 · SwiftUI · AppKit · a forked, no-reflow build of SwiftTerm · XcodeGen.

## License

Copyright © 2026 Ahmed M. Elhalaby. **All rights reserved.** This software is
proprietary — see [LICENSE](LICENSE).
