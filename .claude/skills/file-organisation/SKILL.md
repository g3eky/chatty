---
name: file-organisation
description: Where files go in the Console repo. Use before creating, moving or renaming any file or folder in this project.
---

# File organisation

## Layout
```
README.md          overview for humans and GitHub (top level)
AGENTS.md          guidance for coding agents
PLAN.md            current plan and scope
Package.swift      SwiftPM manifest; the target uses path: "src"
src/               ALL Swift source code, nothing else
scripts/           build and packaging scripts (e.g. make-app.sh)
.claude/skills/    project skills, one folder per skill: .claude/skills/<name>/SKILL.md
```

## Rules
- All source code goes in `src/`. Don't use SwiftPM's default `Sources/<Target>/`.
- Keep `src/` flat until it clearly needs subfolders. Ask before creating a subfolder.
- Shaders are MSL strings inside Swift files in `src/`. There are no `.metal` files, because there is no Metal compiler.
- Scripts go in `scripts/`, never in `src/` or the repo root.
- Build output (`.build/`, `Console.app`) is never committed and must be listed in `.gitignore`.
- New skills go in `.claude/skills/<kebab-case-name>/SKILL.md`, with `name` and `description` frontmatter.
- Keep `README.md` short: what it is, requirements, build/run. Put agent-facing detail in `AGENTS.md`, not the README.
- When the layout changes, update this skill, `AGENTS.md` and `PLAN.md` together.
