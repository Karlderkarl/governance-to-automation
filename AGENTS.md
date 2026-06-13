# Repository Guidelines

## Project Structure & Module Organization
This is a Claude Code **skill-authoring** repository, not an application. Its content is a suite of skills that implement a two-stage **governance → automation** pipeline for *other* projects:
- `.agents/skills/prd-to-governance/` — **vendored** from GitHub (`Karlderkarl/prd-to-governance`, tracked by `skills-lock.json` with a content hash). Generates the four governance files (`SOUL.md`, `AGENTS.md`, `CLAUDE.md`, `MEMORY.md`). Prefer sending fixes upstream over editing the vendored copy in place.
- `.agents/skills/governance-to-automation/` — **locally authored**. Reads governance and generates a project-tailored, stack-agnostic `auto-develop.sh`.

Each skill is a `SKILL.md` (YAML frontmatter + workflow) plus a `references/` folder of on-demand blueprints. The `examples/` folder holds **sample outputs** (`auto-develop.payload-sample.sh`, `refact-todo.md`) generated for a Node/pnpm + Payload CMS project — read-only fixtures, not this repository's own build system, and the sample script must not be run here (it carries that project's opt-in privileged defaults). `CLAUDE.md` holds the detailed architecture and the contract between the two skills — read it first.

## Build, Test, and Development Commands
There is no application toolchain (Markdown + one example Bash script). The meaningful checks:
- `bash -n examples/auto-develop.payload-sample.sh` — syntax-check the example pipeline script
- `shellcheck examples/auto-develop.payload-sample.sh` — lint the script, if available
- `rg --files -uu` — list all files incl. hidden (skill inventory)

When `governance-to-automation` generates a script, validate it the same way (`bash -n`, `shellcheck`, then `--dry-run`) before running. Generation must never execute the real loop.

## Coding Style & Naming Conventions
Match the style of the files you touch. Skills share a vocabulary: uncertainty markers (`[NEEDS GOVERNANCE]`, `[NEEDS PRD CLARIFICATION]`, `[NEEDS CODEBASE DISCOVERY]`, `[USER DECISION REQUIRED]`, `[GOVERNANCE DRIFT]`), priority levels (**Critical** / **Required** / **Advisory**), "link, don't duplicate" (read governance, never copy large text), and stack-agnostic generation (never assume a toolchain). Prefer lowercase-hyphenated Markdown filenames such as `task-list-template.md`.

## Testing Guidelines
No test framework. Validate changes by syntax- and lint-checking scripts and dry-running generated pipelines. When changing either skill, keep the governance ↔ automation **memory-discipline invariants** aligned on both sides (diff exclusion of `MEMORY.md`, single overwritten "Next Up" line, archive-only completed work, no-op fix detection, `Depends on #N` blocking) — see `CLAUDE.md`.

## Commit & Pull Request Guidelines
Use Conventional Commit prefixes (`feat:`, `fix:`, `docs:`, `chore:`). Keep commits scoped to one concern. Pull requests should state the purpose, summarize the changed files, and note verification (`bash -n` / `shellcheck` / `--dry-run`).

## Security & Configuration Tips
`.gitignore` excludes `.claude/settings.local.json` (local tooling config — never commit secrets, tokens, or machine-specific credentials). Privileged flags in generated scripts (`bypassPermissions`, `danger-full-access`, auto-merge) are **off by default** and require explicit user opt-in. The automation pipeline may write only `MEMORY.md` plus generated artifacts; `SOUL.md`/`AGENTS.md`/`CLAUDE.md` are never edited by it — corrections route back through `prd-to-governance`.
