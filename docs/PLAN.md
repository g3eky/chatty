# Chatty — v1 Plan

A personal, native macOS terminal with GPU (Metal) rendering.

## Decisions
- **Core:** SwiftTerm handles the PTY, VT parsing and screen grid. We write the Metal renderer, input handling and the app.
- **Layout:** Swift Package (no Xcode project).
- **Scope:** one window only. Tabs, splits, signing and auto-update come later.
- **Toolchain:** Command Line Tools only (no Xcode.app, no `metal` compiler), with Swift 6.4 on macOS 27. **Shaders are compiled at runtime** from an embedded MSL string via `device.makeLibrary(source:options:)`.
- **Minimum macOS:** 14.

## Dependency
- `SwiftTerm` (github.com/migueldeicaza/SwiftTerm), pinned to its latest release tag. We use only the headless parts: `Terminal`, `TerminalDelegate`, `LocalProcess`, `LocalProcessDelegate`. We do **not** use its `TerminalView` (it uses CoreGraphics, not Metal).

## Files
```
README.md                           short overview, requirements, build/run instructions
Package.swift                       executable target "Chatty" with path "src", macOS 14+, depends on SwiftTerm
.gitignore                          .build/, dist/, .DS_Store
src/App/main.swift                  NSApplication setup, AppDelegate, one NSWindow, basic menu (Quit, Copy, Paste)
src/Terminal/TerminalView.swift     NSView backed by CAMetalLayer; owns Terminal + LocalProcess; keyboard,
                                    NSTextInputClient (IME), mouse selection, copy/paste, scroll wheel, resize
src/Rendering/Renderer.swift        Metal device/queue/pipelines, embedded MSL source, instanced cell drawing
src/Rendering/GlyphAtlas.swift      Core Text rasterization of glyphs into an MTLTexture atlas, with a cache
src/Settings/Settings.swift         settings model, ~/.config/chatty/config.yaml read/write (Yams)
src/Settings/SettingsWindow.swift   Settings dialog (fonts)
scripts/make-app.sh                 wraps the release binary into dist/Chatty.app with a minimal Info.plist
scripts/make-icon.swift             draws the app icon for make-app.sh
docs/PLAN.md                        this plan
.claude/skills/                     project skills for Claude Code (see file-organisation)
```

## Design
1. **PTY / core.** `LocalProcess` starts `$SHELL -l` with `TERM=xterm-256color`. Output bytes → `terminal.feed(byteArray:)` on the main queue → mark the view dirty. Keyboard bytes → `process.send(data:)`. On resize, compute cols/rows from cell size, then call `terminal.resize(cols:rows:)` and update the PTY window size.
2. **Rendering.**
   - `CAMetalLayer` (bgra8Unorm, `contentsScale` = backing scale).
   - Draw only when the view is dirty, driven by the view's `CADisplayLink` (ProMotion-aware).
   - Each frame, walk the visible rows and build one instance buffer per pass:
     - **bg pass:** one quad per cell with a non-default background.
     - **glyph pass:** one quad per non-space cell, with atlas UVs and fg colour. The fragment shader samples the atlas alpha and multiplies by colour; colour emoji are sampled as RGBA.
     - **cursor/selection pass:** a few quads.
   - That's 3 draw calls per frame. Uniforms: viewport size and cell size.
3. **Glyph atlas.**
   - Font: `NSFont.monospacedSystemFont` (SF Mono) by default.
   - Cell size comes from advance width and ascent+descent+leading, rounded to device pixels.
   - Glyphs are rasterized with `CTFontDrawGlyphs` into a CGContext at backing scale, then copied into a 2048² texture with a shelf packer.
   - The cache key is (character, bold, italic). Font fallback uses `CTFontCreateForString`, so emoji and CJK work. Wide characters get double-width quads.
4. **Colours.** Use SwiftTerm attributes: the 16 ANSI colours, 256-colour cube, truecolor, inverse, bold, dim, underline (drawn as an extra quad).
5. **Input.**
   - `keyDown` goes through `interpretKeyEvents`. Plain text arrives via `insertText`; special keys (arrows, Home/End, PgUp/PgDn, F-keys, Ctrl+letters) map to escape sequences, respecting application-cursor mode. Option-as-Meta is off by default.
   - Implement `NSTextInputClient` (marked text drawn inline at the cursor) so IME and emoji input work.
   - ⌘C / ⌘V use NSPasteboard; bracketed paste is applied if the mode is enabled.
6. **Scrollback and selection.**
   - The scroll wheel moves a viewport offset into scrollback. When the app enables mouse reporting, wheel and mouse events are forwarded instead.
   - Mouse drag selects text; ⌘C copies it.
7. **Lifecycle.** When the process exits, the window closes. When the last window closes, the app quits.

## Out of scope for v1
Tabs, splits, settings UI, themes/config file, ligatures, hyperlinks, notifications, quick-terminal, signing/notarization, auto-update.

## Verification
- `swift build` succeeds with CLT only (no Xcode).
- `swift run Chatty` opens a window running a login shell.
- Manual checks:
  - `ls --color`
  - 256-colour test: `for i in (seq 0 255); printf "\e[48;5;%dm %3d " $i $i; end; printf "\e[0m\n"`
  - truecolor `printf "\e[48;2;255;100;0m X \e[0m\n"`
  - `vim` (alt screen, cursor keys)
  - `htop` (resize while running)
  - `tmux`
  - emoji 👍 and CJK 日本語 widths
  - Japanese IME input with inline marked text
  - copy/paste, scroll back through `seq 1 5000`
  - window resize reflows rows/cols
- GPU check: `MTL_HUD_ENABLED=1 swift run Chatty` shows the Metal performance HUD (fps / GPU time). `yes` should keep running smoothly without high CPU in Activity Monitor.
- `scripts/make-app.sh` produces `dist/Chatty.app`, which launches by double-click.
