# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-06-19

### Added
- **Optional test-discipline contract** for generated pipelines: a `TEST_POLICY`
  (`off` / `preferred` / `required`), an explicit `TEST_ELIGIBILITY[]` matcher set, and a
  `TARGETED_TEST_CMD` carrying a `{TARGET}` token. Entirely absent fields are the valid
  backward-compatible default (`off`) — existing governance keeps generating identical scripts.
- **Deterministic test-eligibility resolution** (`resolve_test_policy`), mirroring skill
  resolution: only explicit `label:` / `title:` `include`/`except` matchers, resolved once per
  task and logged to `test-policy.log`. No "ambiguous" outcome — **`except` wins over `include`**,
  then an `include` match is eligible, otherwise the base default follows the **declared,
  well-formed** matchers (allowlist when usable `include`s are declared, denylist when only usable
  `except`s are). A dead matcher (unknown type, invalid `title:` regex, malformed entry) is warned
  and never arms the denylist base; an empty/inert set fails safe to `off` and warns
  (`[NEEDS GOVERNANCE]`) — it never falls through to "test every task".
- **Targeted RED→GREEN gate** (`run_targeted_test_gate` + a test-first sub-phase): for eligible
  tasks the model authors the test *before* implementation and the script proves a non-zero (RED)
  result first, then reruns the **same** target after implementation. The validated RED target is
  frozen (`FROZEN_TARGETED_TEST_TARGET`) and reused for every GREEN rerun, so the proven transition
  cannot be swapped for an always-green test. The hard, blocking gate (`TEST_GATE_ACTIVE`) is armed
  **only under `required`**; under `preferred` a still-red target stays **advisory** and never
  hard-blocks or discards correctness work.
- **Asymmetric review enforcement**: `required` missing-tests are blocking numbered findings;
  `preferred` missing-tests use a non-blocking `ADVISORY:` channel (a leading `LGTM` followed by
  `ADVISORY:` lines still passes), so `preferred` can never silently collapse into `required`.
- The test-discipline wiring is **task-source-general** — it is generated for the local task-list /
  MEMORY.md variants as well as the GitHub-issue path (with `label:` matchers inert where a source
  has no labels, exactly like skill resolution).

### Security
- The model-authored `{TARGET}` value reaches an `eval`'d command, so the script **sanitizes** it
  against a strict allowlist (`^[][A-Za-z0-9_./:@=+#-]+$`) before substitution — rejecting (or, under
  `preferred`, downgrading to advisory) any target containing shell metacharacters.

### Changed
- Honest-scope documentation: the gate is a **targeted TDD gate, not a full no-regression gate**.
  It proves only the one designated test's red→green transition; broad regression coverage remains
  whatever `CHECKS[]` already runs. A `required` policy without a `TARGETED_TEST_CMD` is degraded to
  `preferred` with a logged `[GOVERNANCE DRIFT]` rather than pretending a hard gate exists.

## [1.1.4] - 2026-06-15

### Fixed
- Generated pipelines now **branch each issue from the base branch** (not the current HEAD) and
  return to the base branch after opening the PR. Previously, a `--max-issues > 1` run branched
  issue N off issue N-1's still-unmerged tip, so issue N's review diff included the previous
  issue's code.
- The correctness checkpoint commit is now gated on a **non-empty code diff** (excluding
  `MEMORY.md`/logs) instead of any repo change. Because `run_review` auto-approves an empty code
  diff, a model that only rewrote the `MEMORY.md` "Next Up" line could previously pass review and
  produce a memory-only "implemented" commit and PR.
- Failure paths now roll back via a `return_to_base` helper that **discards** in-progress work
  (`git reset --hard` + `git clean -fd -e "$LOGDIR"`) before returning to the base branch, instead
  of a bare `git checkout "$orig"` that could block the checkout or carry half-written changes onto
  the base branch (tripping the next run's clean-worktree guard). The `clean` excludes the log dir
  so the failing issue's diagnostic logs survive even if `logs/` was never gitignored; the refactor
  revert excludes it the same way.
- No-op/refactor convergence detection now hashes the code diff with `git hash-object --stdin`
  instead of `md5sum`, which is absent by default on macOS/Windows and would make a generated
  script die under `set -euo pipefail` — restoring the documented "bash + git + gh only" contract.

### Changed
- README clarifies that the `examples/` fixture is a **pre-refactor** snapshot, not a current
  reference for the refactor-pass invariants.

## [1.1.3] - 2026-06-15

### Fixed
- Fix and refactor prompts now explicitly read `MEMORY.md`'s Update Rules before updating
  `"Next Up"`, keeping every prompt that mutates memory aligned with the governance memory
  discipline.

## [1.1.2] - 2026-06-15

### Fixed
- Every write-capable prompt now forbids editing `CLAUDE.md` alongside `SOUL.md` and `AGENTS.md`
  (implement, fix, refactor, check-fix, memory, plus the generation rule). The guard previously
  named only `SOUL.md`/`AGENTS.md`, so an agent could edit `CLAUDE.md` and have it staged into the
  issue commit — contradicting the contract that the pipeline writes only `MEMORY.md` + artifacts.
- The implementation prompt now sets the "Next Up" status line with explicit overwrite semantics
  ("overwrite, do not append") instead of "add ONE", matching the fix prompt and the
  overwrite-never-append memory invariant so reruns can't grow the status line.

### Changed
- `SECURITY.md` supported-versions table updated to `1.1.x` to match the latest release.

## [1.1.1] - 2026-06-15

### Fixed
- `resolve_skill` no longer silently skips a configured skill when a `title:` matcher holds an invalid
  regex: the diagnostic is suppressed, the `[[ =~ ]]` status-2 case is detected, and an explicit
  invalid-policy warning is recorded in `skill-resolution.log` (plus a run-log WARN line).
- The memory-update prompt now carries the "Do NOT commit" guard required of every write-capable prompt
  (the pipeline owns the commit) and instructs the agent to read MEMORY.md's Update Rules first.

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

[1.2.0]: https://github.com/Karlderkarl/governance-to-automation/releases/tag/v1.2.0
[1.1.4]: https://github.com/Karlderkarl/governance-to-automation/releases/tag/v1.1.4
[1.1.3]: https://github.com/Karlderkarl/governance-to-automation/releases/tag/v1.1.3
[1.1.2]: https://github.com/Karlderkarl/governance-to-automation/releases/tag/v1.1.2
[1.1.1]: https://github.com/Karlderkarl/governance-to-automation/releases/tag/v1.1.1
[1.1.0]: https://github.com/Karlderkarl/governance-to-automation/releases/tag/v1.1.0
[1.0.0]: https://github.com/Karlderkarl/governance-to-automation/releases/tag/v1.0.0
