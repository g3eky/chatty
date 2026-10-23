# AGENTS.md

Guidance for coding agents working in this repo.

## Project
Console is a personal, native macOS terminal emulator. It renders with Metal, and its UI is AppKit. SwiftTerm provides the PTY, the escape-code (VT) parser and the screen grid. Everything else (the Metal renderer, the glyph atlas, input handling and the app) lives in this repo. See `PLAN.md` for the v1 design and scope.

## Toolchain constraints
- Only the Command Line Tools are installed: there is **no Xcode.app** and **no `metal` compiler**.
- Build with SwiftPM only. Don't add an `.xcodeproj` or `.metal` files.
- Shaders are MSL source strings compiled at runtime with `MTLDevice.makeLibrary(source:options:)`.
- Swift 6.4, minimum deployment target macOS 14.

## Commands
- Build: `swift build`
- Run: `swift run Console`
- Run with the Metal HUD: `MTL_HUD_ENABLED=1 swift run Console`
- Make an app bundle: `scripts/make-app.sh` (produces `Console.app`)

## Layout
All source code lives in `src/` (`Package.swift` sets the target `path: "src"`). The full rules are in `.claude/skills/file-organisation/SKILL.md`.
- `src/main.swift`: app entry point, AppDelegate, window, menu
- `src/TerminalView.swift`: the CAMetalLayer-backed view; owns the SwiftTerm `Terminal` and `LocalProcess`; handles input, IME, selection and scrolling
- `src/Renderer.swift`: Metal pipelines, embedded shaders, instanced draws
- `src/GlyphAtlas.swift`: Core Text glyph rasterization into a texture atlas
- `scripts/`: build and packaging scripts
- `.claude/skills/`: project skills for Claude Code
- `README.md`: overview for humans and GitHub

## Rules
- Do only what was asked. No unrequested refactors, renames, reformatting or extra features.
- Ask before adding dependencies, new folders, or more than one new file, and before deleting anything you didn't create.
- Stay within v1 scope in `PLAN.md` unless told otherwise.
- Use only SwiftTerm's headless API (`Terminal`, `LocalProcess`), never its `TerminalView`.
- Only draw when something changed. Keep it to one instance buffer per pass and a few draw calls per frame.
- Keep the main thread free of blocking work. PTY reads arrive asynchronously and are fed to the terminal on the main queue.
- Match the existing code style. Write the least code that solves the problem.

## Done means
- `swift build` passes with no new warnings.
- The change is checked by running the app, using the relevant checks from the Verification section of `PLAN.md`.
- Report what was checked and the actual results, including failures.
