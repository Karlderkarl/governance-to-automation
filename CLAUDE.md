# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a **Claude Code skill-authoring repository**. It does not contain an application — its "source" is the **`governance-to-automation`** skill (Markdown + one example shell script): the second stage of a two-stage **governance → automation** pipeline for *other* projects. The first stage, **`prd-to-governance`**, is a **separate skill** at [github.com/Karlderkarl/prd-to-governance](https://github.com/Karlderkarl/prd-to-governance) — it is **not** vendored or shipped here.

```
Idea/PRD ─▶ prd-to-governance ─▶ SOUL.md / AGENTS.md / CLAUDE.md / MEMORY.md ─▶ governance-to-automation ─▶ auto-develop.sh
            (separate skill/repo)       (the governance contract)              (this repo)                  (runs autonomously)
```

- **`prd-to-governance`** (separate repo) — turns a PRD + repo reality into the four governance files; defines **how and where memory is managed** (`MEMORY.md` vs `memory/completed-phases.md`, status-line discipline, drift markers). Its repo is the source of truth for the governance-file structure and update rules; this repo only *references* it.
- **`.agents/skills/governance-to-automation/`** — the skill this repo authors and ships. Reads the governance files and *generates* a project-tailored `auto-develop.sh` (plus task source, prompt builders, logging). It does **not** implement features; it writes the machinery that does.

## The contract with prd-to-governance (most important architecture)

This skill is deliberately coupled to `prd-to-governance` through **memory-management discipline**. `prd-to-governance` declares the rules in `MEMORY.md`'s *Update Rules*; `governance-to-automation` must encode the *exact same* rules into every `auto-develop.sh` it generates. Keep these invariants aligned with what `prd-to-governance` defines (its repo is authoritative):

- Review diffs **exclude** `MEMORY.md` (`git diff <base> -- . ':!MEMORY.md'`) so status churn never bloats reviewer context.
- The implement/fix steps write **one overwritten** "Next Up" line — never append.
- Only a dedicated post-review memory step writes completed work, and it writes to `memory/completed-phases.md`, not inline.
- **No-op fix detection**: if a fix cycle changes only `MEMORY.md`/logs, remaining findings are accepted and the review loop breaks (prevents infinite loops).
- `Depends on #N` hard-blocks a task until its dependencies are done.

A second boundary: the automation may write **only `MEMORY.md`** + generated artifacts. `SOUL.md`/`AGENTS.md`/`CLAUDE.md` are never edited by the pipeline — corrections route back through `prd-to-governance` in Audit mode.

## Skill anatomy & authoring conventions

The skill is a directory with `SKILL.md` (YAML frontmatter `name` + `description`, then the workflow) and a `references/` folder of structural blueprints loaded on demand. Conventions to match when editing the skill:

- **Uncertainty markers**: `[NEEDS GOVERNANCE]`, `[NEEDS PRD CLARIFICATION]`, `[NEEDS CODEBASE DISCOVERY]`, `[USER DECISION REQUIRED]`, `[GOVERNANCE DRIFT]`.
- **Priority levels**: **Critical** / **Required** / **Advisory**, used only where they sharpen real stakes.
- **Link, don't duplicate**: prompts and references instruct agents to *read* the governance files rather than copying large governance text (single source of truth).
- **Stack-agnostic**: `governance-to-automation` must never assume a toolchain. Validation commands come verbatim from the target project's `CLAUDE.md` into a `CHECKS=()` array; an empty array is a valid no-op. Do not reintroduce `package.json`/runtime guards or hardcode npm/pnpm/uv/cargo as a default.
- **Deterministic skill resolution**: when the generated pipeline designates a task-specific skill, the decision comes from explicit governance/user-approved `SKILL_MAP` matchers — only `label:` and `title:` types, both resolved without touching the filesystem — and is logged once per task. Do not add registry lookup, network discovery, free semantic search, or a filesystem-dependent `path:` matcher as a hard decision basis; ambiguity must resolve to no injection rather than guessing.
- **Deterministic test resolution** (optional, opt-in): test eligibility follows the *same* discipline as skill resolution — only explicit `label:` / `title:` `TEST_ELIGIBILITY` matchers, resolved without touching the filesystem and logged once per task. `TEST_POLICY` absent/empty is the valid default (`off`); resolution has **no "ambiguous" outcome** (`except` wins over `include`, then `include`, then a base default from the *declared, well-formed* matchers), and an empty/inert set fails safe to `off` — never "test every task". The gate is a **targeted red→green proof for one designated test, not a full no-regression gate**; the hard blocking gate is armed only under `required`, while `preferred` stays advisory and must never hard-block or discard correctness work. The model-authored `{TARGET}` reaches an `eval`, so it is sanitized against a strict allowlist before substitution. Do not add a heuristic "this probably needs tests" detector or framework-specific exit-code parsing (stay stack-agnostic).
- **One project = one folder**; the governance files and `memory/` live together at the project root.
- Privileged flags in generated scripts (`bypassPermissions`, `danger-full-access`, auto-merge) are **off by default** and require explicit user opt-in. The privileged values are never hardcoded as defaults; generated scripts ship safe modes (`default` / `workspace-write`) and reach privileged ones only via the runtime `--unattended` / `--auto-merge` flags behind a `confirm_privileged_mode` gate (lists the privileges, prompts `[y/N]`, skipped by `--dry-run`/`--yes`, refuses without a TTY). The `tmux` re-exec propagates the opt-in plus `--yes` so the human confirms once in the foreground.

## Reference artifacts at the repo root

`examples/auto-develop.payload-sample.sh` and `examples/refact-todo.md` are **example outputs**, not this repository's own build system. They were generated for a Node/pnpm + Payload CMS project and are kept under `examples/` as the concrete model that `governance-to-automation`'s template generalizes. Do **not** treat their `pnpm type-check/lint/build` commands or Payload-specific rules as applicable to this repo, and do **not** run the sample script here. The sample now mirrors the skill's safe-by-default policy: privileged modes (`bypassPermissions`, `danger-full-access`) and auto-merge are **off** unless opted in via `--unattended` / `--auto-merge` and confirmed at runtime — they are no longer hardcoded defaults. (`examples/refact-todo.md` also illustrates the local task-list task source, in the Option B schema.)

## Commands

This repo has no build/lint/test toolchain (it is Markdown + one example bash script). The only meaningful checks:

```bash
bash -n examples/auto-develop.payload-sample.sh    # syntax-check the example pipeline script
shellcheck examples/auto-develop.payload-sample.sh # lint the script, if shellcheck is available
rg --files -uu                                     # list all files incl. hidden (skill inventory)
```

When `governance-to-automation` generates a script, validate it the same way (`bash -n`, `shellcheck`, then `--dry-run`) before it is run — generation must never execute the real loop.

## Caveats

- The root **`AGENTS.md`** describes this repo's own contributor guidelines (structure, checks, conventions). It is *not* a governance file produced by `prd-to-governance` — do not treat it as pipeline input. There is currently no `SOUL.md` or `MEMORY.md` in this repo, so do not add `@SOUL.md`/`@MEMORY.md` references that point at nonexistent files.
- `.gitignore` excludes `.claude/settings.local.json`.
