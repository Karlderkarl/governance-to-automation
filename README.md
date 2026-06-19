# Governance Skills

Turn project requirements into governance files, then turn that governance into an automated
implementation pipeline. **This repository ships the `governance-to-automation` skill.**
`prd-to-governance` is a separate, companion skill with its own repo.

## Skills

- **`governance-to-automation`** — *this repo*
  Generate and keep in sync an issue-driven `auto-develop.sh` pipeline (implement → check →
  dual-review → fix → refactor → re-review → commit → PR) plus its task source, prompt builders,
  and logging, from existing governance. Supports an **optional, opt-in test-discipline gate**:
  a deterministic per-task test policy and a targeted red→green check, off by default and
  backward-compatible when governance declares no test fields.
- **`prd-to-governance`** — *separate skill:* <https://github.com/Karlderkarl/prd-to-governance>
  Create, update, and audit `SOUL.md`, `AGENTS.md`, `CLAUDE.md`, and `MEMORY.md` from a PRD and the
  current repository state. It owns the **structure and update rules** of those governance files
  (including `MEMORY.md`); `governance-to-automation` consumes them.

## Install

```bash
npx skills add Karlderkarl/governance-to-automation
```

The companion skill installs from its own repo:

```bash
npx skills add Karlderkarl/prd-to-governance
```

Requires [Claude Code](https://claude.ai/code).

## Repository Layout

The skill definition lives in `.agents/skills/`:

- `.agents/skills/governance-to-automation/SKILL.md` — entry point
- `.agents/skills/governance-to-automation/references/` — structural blueprints
  (`auto-develop-template.md`, `prompt-builders.md`, `task-list-template.md`, `extraction-checklist.md`)
- `examples/` — a fully-resolved **pre-refactor** sample output (read-only fixture; it predates
  the refactor pass and is intentionally not re-synced — see the template for current invariants)
