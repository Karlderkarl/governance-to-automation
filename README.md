# governance-to-automation

A Claude Code skill that turns your project **governance** (`SOUL.md` / `AGENTS.md` / `CLAUDE.md` / `MEMORY.md`) into a runnable, **stack-agnostic** auto-develop pipeline — the execution counterpart to [`prd-to-governance`](https://github.com/Karlderkarl/prd-to-governance).

```
PRD ─▶ prd-to-governance ─▶ governance files ─▶ governance-to-automation ─▶ auto-develop.sh
        (what & how to build)                      (generates the build loop)   (runs autonomously)
```

## Install

```bash
npx skills add Karlderkarl/governance-to-automation
```

Requires [Claude Code](https://claude.ai/code).

## Usage

Once installed, Claude Code auto-selects the skill when you ask it to automate the build loop for a project that already has governance files. You can also invoke it explicitly:

```
@governance-to-automation generate the auto-develop pipeline from my governance files
```

It reads your four governance files, confirms the strategic choices it must not infer (models per step, review depth, merge policy, sandbox level), then generates a project-tailored `auto-develop.sh` and validates it (`bash -n`, `shellcheck`, `--dry-run`) before anything runs.

## What it does

From your governance, the skill generates the machinery that builds the project end to end:

| Artifact | Purpose |
|---|---|
| `auto-develop.sh` | The pipeline: select task → implement → check → review → fix → **refactor → re-review** → commit → PR. Parameterized to your project. |
| Task source wiring | GitHub Issues (label + `Depends on #N`) **or** a local task-list file — one source of truth, chosen with you. |
| Prompt builders | Implementation / review / fix / refactor / memory prompts, with your SOUL/AGENTS rules injected and "read the governance first" baked in. |
| Logs + ignore rules | `logs/issues/<n>/` layout and a `.gitignore` entry so pipeline logs never pollute commits or review diffs. |

The skill does **not** implement features itself — it writes the automation that does, wired to the exact memory-management discipline your governance prescribes.

## Two-pass pipeline: correctness, then refactor

Each task runs through two review-backed passes:

1. **Correctness** — implement → check → reviewers A/B → fix → re-review, until both approve.
2. **Refactor** — the approved state is committed as a checkpoint, then the code is simplified to senior-engineer quality (behavior-preserving) and **re-validated by the same reviewers**. A refactor round is kept only on a clean re-review; otherwise it reverts to the checkpoint. So a degraded refactor is never kept and approved work is never lost. Disable with `--no-refactor`.

## Modes

- **Generate** — no automation yet; create `auto-develop.sh` and its supporting artifacts from the governance.
- **Audit/Sync** — automation exists; compare it to current governance, report drift, update on approval.
- **Validate** — lint / dry-run an existing or freshly generated script without running the real loop.

The skill is **stack-agnostic**: validation commands come verbatim from your `CLAUDE.md` (npm/pnpm, uv/poetry, cargo, go, make, or none). Privileged flags (`bypassPermissions`, `danger-full-access`, auto-merge) are off by default and require explicit opt-in.

## Repository structure

```
.agents/skills/governance-to-automation/
  SKILL.md                       # Skill definition (entry point)
  references/
    auto-develop-template.md     # The pipeline script blueprint
    prompt-builders.md           # Implementation/review/fix/refactor/memory prompts
    task-list-template.md        # Local task-source format (and GitHub-issue seeding)
    extraction-checklist.md      # governance → script parameter mapping
examples/
  auto-develop.payload-sample.sh # A fully-resolved sample output (read-only fixture)
  refact-todo.md                 # A sample local task list
```

## Pairs with

[`prd-to-governance`](https://github.com/Karlderkarl/prd-to-governance) generates the governance files this skill consumes. Use it first; use this one to automate the build loop.
