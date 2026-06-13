# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a **Claude Code skill-authoring repository**. It does not contain an application — its "source" is a suite of skills (Markdown + one example shell script) that implement a two-stage **governance → automation** pipeline for *other* projects:

```
Idea/PRD ─▶ prd-to-governance ─▶ SOUL.md / AGENTS.md / CLAUDE.md / MEMORY.md ─▶ governance-to-automation ─▶ auto-develop.sh
            (what & how to build)        (the governance contract)              (generates the build loop)     (runs autonomously)
```

- **`.agents/skills/prd-to-governance/`** — turns a PRD + repo reality into the four governance files; defines **how and where memory is managed** (`MEMORY.md` vs `memory/completed-phases.md`, status-line discipline, drift markers). **Vendored** from GitHub `Karlderkarl/prd-to-governance` and tracked by `skills-lock.json` (with a content hash) — prefer sending fixes upstream rather than editing the vendored copy in place.
- **`.agents/skills/governance-to-automation/`** — **locally authored**. Reads the governance files and *generates* a project-tailored `auto-develop.sh` (plus task source, prompt builders, logging). It does **not** implement features; it writes the machinery that does.

## The contract between the two skills (most important architecture)

The skills are deliberately coupled through **memory-management discipline**. `prd-to-governance` declares the rules in `MEMORY.md`'s *Update Rules*; `governance-to-automation` must encode the *exact same* rules into every `auto-develop.sh` it generates. When changing either skill, keep these invariants aligned on both sides:

- Review diffs **exclude** `MEMORY.md` (`git diff <base> -- . ':!MEMORY.md'`) so status churn never bloats reviewer context.
- The implement/fix steps write **one overwritten** "Next Up" line — never append.
- Only a dedicated post-review memory step writes completed work, and it writes to `memory/completed-phases.md`, not inline.
- **No-op fix detection**: if a fix cycle changes only `MEMORY.md`/logs, remaining findings are accepted and the review loop breaks (prevents infinite loops).
- `Depends on #N` hard-blocks a task until its dependencies are done.

A second boundary: the automation may write **only `MEMORY.md`** + generated artifacts. `SOUL.md`/`AGENTS.md`/`CLAUDE.md` are never edited by the pipeline — corrections route back through `prd-to-governance` in Audit mode.

## Skill anatomy & authoring conventions

Each skill is a directory with `SKILL.md` (YAML frontmatter `name` + `description`, then the workflow) and a `references/` folder of structural blueprints loaded on demand. Conventions shared across both skills — match them when editing or adding skills:

- **Uncertainty markers**: `[NEEDS GOVERNANCE]`, `[NEEDS PRD CLARIFICATION]`, `[NEEDS CODEBASE DISCOVERY]`, `[USER DECISION REQUIRED]`, `[GOVERNANCE DRIFT]`.
- **Priority levels**: **Critical** / **Required** / **Advisory**, used only where they sharpen real stakes.
- **Link, don't duplicate**: prompts and references instruct agents to *read* the governance files rather than copying large governance text (single source of truth).
- **Stack-agnostic**: `governance-to-automation` must never assume a toolchain. Validation commands come verbatim from the target project's `CLAUDE.md` into a `CHECKS=()` array; an empty array is a valid no-op. Do not reintroduce `package.json`/runtime guards or hardcode npm/pnpm/uv/cargo as a default.
- **One project = one folder**; the governance files and `memory/` live together at the project root.
- Privileged flags in generated scripts (`bypassPermissions`, `danger-full-access`, auto-merge) are **off by default** and require explicit user opt-in.

## Reference artifacts at the repo root

`auto-develop.sh` and `refact-todo.md` at the root are **example outputs**, not this repository's own build system. They were generated for a Node/pnpm + Payload CMS project and are kept as the concrete model that `governance-to-automation`'s template generalizes. Do **not** treat their `pnpm type-check/lint/build` commands or Payload-specific rules as applicable to this repo. (`refact-todo.md` also illustrates the local task-list task source.)

## Commands

This repo has no build/lint/test toolchain (it is Markdown + one example bash script). The only meaningful checks:

```bash
bash -n auto-develop.sh        # syntax-check the example/generated pipeline script
shellcheck auto-develop.sh     # lint the script, if shellcheck is available
rg --files -uu                 # list all files incl. hidden (skill inventory)
```

When `governance-to-automation` generates a script, validate it the same way (`bash -n`, `shellcheck`, then `--dry-run`) before it is run — generation must never execute the real loop.

## Caveats

- The root **`AGENTS.md`** describes this repo's own contributor guidelines (structure, checks, conventions). It is *not* a governance file produced by `prd-to-governance` — do not treat it as pipeline input. There is currently no `SOUL.md` or `MEMORY.md` in this repo, so do not add `@SOUL.md`/`@MEMORY.md` references that point at nonexistent files.
- `.gitignore` excludes `.claude/settings.local.json`.
