# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-06-15

### Added
- Deterministic task-to-skill resolution guidance for generated pipelines via explicit `SKILL_MAP`
  matchers — `label:` and `title:` types only, both resolved without filesystem access — including
  one-time per-task logging and prompt injection only for implementation, fix, and refactor work.

### Changed
- Clarified that skill resolution must not rely on registries, network discovery, semantic search, or
  model guessing; ambiguous matches inject no designated skill.
- Write-capable prompts (implement, fix, check-fix, refactor) now instruct agents to read both
  `SOUL.md` and `AGENTS.md` first, so prohibited actions and role boundaries are never missed.

## [1.0.0] - 2026-06-13

First stable release of the **governance-to-automation** skill.

### Added
- Skill that generates a project-tailored, **stack-agnostic** `auto-develop.sh` pipeline from the
  four governance files (`SOUL.md` / `AGENTS.md` / `CLAUDE.md` / `MEMORY.md`), plus task-source
  wiring, prompt builders, and logging — wired to the memory-management discipline that
  `prd-to-governance` defines.
- **Two-pass pipeline**: a correctness pass (implement → check → dual A/B review → fix) followed by
  a checkpoint-protected **refactor pass** (simplify to senior-engineer quality, re-validated by the
  reviewers; a not-cleanly-approved refactor reverts to the checkpoint, so degraded refactors are
  never kept and approved work is never lost). `--no-refactor` / `--max-refactor-rounds` to control.
- GitHub-issue **seeding** from the AGENTS.md phase plan, and a local task-list source variant.
- First-class **detached runs** via `--tmux-session` / `--tmux-log`.
- Reference blueprints: `auto-develop-template.md`, `prompt-builders.md`, `task-list-template.md`,
  `extraction-checklist.md`; and an `examples/` sample output.
- **skills.sh packaging**: README, MIT `LICENSE`, GitHub topics; ships a single skill
  (`prd-to-governance` is a separate, companion skill with its own repo).

### Fixed
- Review and no-op-detection diffs now include **new (untracked) files** (staged diff against base),
  so a brand-new implementation file can no longer be approved as an empty diff.
- **Safe staging** that does not abort under `set -e` when the log directory is gitignored.
- `--dry-run` is **side-effect-free** (never mutates tracked files).

[1.0.0]: https://github.com/Karlderkarl/governance-to-automation/releases/tag/v1.0.0
