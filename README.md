# Chatty

A native macOS terminal emulator with GPU-accelerated rendering through Metal.

Built with AppKit and Metal, with [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for terminal emulation.

> Status: early development, a personal tool. See [docs/PLAN.md](docs/PLAN.md) for the v1 scope.

## Requirements
- macOS 14 or later
- Swift 6 toolchain (Command Line Tools are enough; Xcode is not required)

## Build and run
```sh
swift build
swift run Chatty
```

To build an app bundle:
```sh
scripts/make-app.sh
open dist/Chatty.app
```

## Project layout
- `src/`: source code, grouped by area (`App/`, `Terminal/`, `Rendering/`, `Settings/`)
- `scripts/`: build and packaging scripts
- `docs/`: plan and design notes
- `dist/`: built app bundle (not committed)
- `.claude/skills/`: Claude Code project skills
