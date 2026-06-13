# Repository Guidelines

## Project Structure & Module Organization
This is a Claude Code **skill-authoring** repository, not an application. It ships **one skill**, `governance-to-automation` — the second stage of a two-stage **governance → automation** pipeline for *other* projects. The first stage, `prd-to-governance`, is a **separate skill** at `github.com/Karlderkarl/prd-to-governance` (not vendored here).
- `.agents/skills/governance-to-automation/` — the skill this repo authors. Reads governance and generates a project-tailored, stack-agnostic `auto-develop.sh`.

The skill is a `SKILL.md` (YAML frontmatter + workflow) plus a `references/` folder of on-demand blueprints. The `examples/` folder holds **sample outputs** (`auto-develop.payload-sample.sh`, `refact-todo.md`) generated for a Node/pnpm + Payload CMS project — read-only fixtures, not this repository's own build system, and the sample script must not be run here (it carries that project's opt-in privileged defaults). `CLAUDE.md` holds the detailed architecture and the contract with `prd-to-governance` — read it first.

## Build, Test, and Development Commands
There is no application toolchain (Markdown + one example Bash script). The meaningful checks:
- `bash -n examples/auto-develop.payload-sample.sh` — syntax-check the example pipeline script
- `shellcheck examples/auto-develop.payload-sample.sh` — lint the script, if available
- `rg --files -uu` — list all files incl. hidden (skill inventory)

When `governance-to-automation` generates a script, validate it the same way (`bash -n`, `shellcheck`, then `--dry-run`) before running. Generation must never execute the real loop.

## Coding Style & Naming Conventions
Match the style of the files you touch. Skills share a vocabulary: uncertainty markers (`[NEEDS GOVERNANCE]`, `[NEEDS PRD CLARIFICATION]`, `[NEEDS CODEBASE DISCOVERY]`, `[USER DECISION REQUIRED]`, `[GOVERNANCE DRIFT]`), priority levels (**Critical** / **Required** / **Advisory**), "link, don't duplicate" (read governance, never copy large text), and stack-agnostic generation (never assume a toolchain). Prefer lowercase-hyphenated Markdown filenames such as `task-list-template.md`.

## Testing Guidelines
No test framework. Validate changes by syntax- and lint-checking scripts and dry-running generated pipelines. When changing the skill, keep the **memory-discipline invariants** aligned with what `prd-to-governance` defines (diff exclusion of `MEMORY.md`, single overwritten "Next Up" line, archive-only completed work, no-op fix detection, `Depends on #N` blocking) — see `CLAUDE.md`.

## Commit & Pull Request Guidelines
Use Conventional Commit prefixes (`feat:`, `fix:`, `docs:`, `chore:`). Keep commits scoped to one concern. Pull requests should state the purpose, summarize the changed files, and note verification (`bash -n` / `shellcheck` / `--dry-run`).

## Security & Configuration Tips
`.gitignore` excludes `.claude/settings.local.json` (local tooling config — never commit secrets, tokens, or machine-specific credentials). Privileged flags in generated scripts (`bypassPermissions`, `danger-full-access`, auto-merge) are **off by default** and require explicit user opt-in. The automation pipeline may write only `MEMORY.md` plus generated artifacts; `SOUL.md`/`AGENTS.md`/`CLAUDE.md` are never edited by it — corrections route back through `prd-to-governance`.
