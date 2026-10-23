---
name: file-organisation
description: Where files go in the Chatty repo. Use before creating, moving or renaming any file or folder in this project.
---

# File organisation

## Layout
```
README.md          overview for humans and GitHub (top level)
AGENTS.md          guidance for coding agents (top level, where agents look for it)
Package.swift      SwiftPM manifest; the target uses path: "src"
Package.resolved   pinned dependency versions
src/               ALL Swift source code, nothing else, grouped by area:
  App/               entry point, app delegate, menus
  Terminal/          terminal view, PTY wiring, input
  Rendering/         Metal renderer and glyph atlas
  Settings/          settings model, config file I/O, settings dialog
scripts/           build and packaging scripts (make-app.sh, make-icon.swift)
docs/              plan and design notes (PLAN.md)
dist/              build output from scripts/make-app.sh (Chatty.app); ignored
.claude/skills/    project skills, one folder per skill: .claude/skills/<name>/SKILL.md
```

## Rules
- The top level holds only the files above. Everything else goes in a folder.
- All source code goes in `src/`. Don't use SwiftPM's default `Sources/<Target>/`.
- Put each source file in the `src/` area folder it belongs to. Don't add files directly under `src/`. Ask before creating a new area folder.
- Shaders are MSL strings inside Swift files in `src/Rendering/`. There are no `.metal` files, because there is no Metal compiler.
- Scripts go in `scripts/`, never in `src/` or the repo root.
- Docs other than `README.md` and `AGENTS.md` go in `docs/`.
- Build output (`.build/`, `dist/`) and `.DS_Store` are never committed and are listed in `.gitignore`.
- New skills go in `.claude/skills/<kebab-case-name>/SKILL.md`, with `name` and `description` frontmatter.
- Keep `README.md` short: what it is, requirements, build/run. Put agent-facing detail in `AGENTS.md`, not the README.
- When the layout changes, update this skill, `AGENTS.md` and `docs/PLAN.md` together.
