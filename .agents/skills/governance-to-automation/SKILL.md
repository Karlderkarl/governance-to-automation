---
name: governance-to-automation
description: "Generate (and keep in sync) the automation that executes a project's governance. From the governance files (SOUL.md, AGENTS.md, CLAUDE.md, MEMORY.md) this skill produces a project-tailored, stack-agnostic issue-driven auto-develop pipeline script plus its task source, prompt builders, and logging — wired to the exact memory-management discipline that prd-to-governance defines. Use after governance exists and the user wants the build loop automated."
---

# Governance to Automation

This skill **generates the automation** that runs a project end to end. It is the execution counterpart to `prd-to-governance`:

- `prd-to-governance` is a **separate skill** — [github.com/Karlderkarl/prd-to-governance](https://github.com/Karlderkarl/prd-to-governance) — that produces the four governance files (`SOUL.md`, `AGENTS.md`, `CLAUDE.md`, `MEMORY.md`) and defines **how and where memory is managed** (what goes into `MEMORY.md` vs `memory/completed-phases.md`, the status-line discipline, drift handling). **For the structure and update rules of `MEMORY.md` and the other governance files, see that skill.**
- `governance-to-automation` (this skill) reads that governance and **emits the runnable pipeline** — primarily an `auto-develop.sh` script that processes tasks autonomously: implement → check → review → fix → refactor → re-review → commit → PR. The script *embodies* the memory rules the governance prescribes.

The skill does **not** itself implement features. It writes the machinery that does, configured to one specific project's contract.

For this skill, one project equals one folder. The project root is the folder that contains the governance files. Read and write only inside it unless the user says otherwise.

## What this skill produces

| Artifact | Purpose |
|---|---|
| `auto-develop.sh` | The pipeline. Selects eligible tasks, runs implement/check/review/fix loop, then a senior-quality refactor pass re-validated by the reviewers, commits, opens PR, updates memory. Parameterized to this project. |
| Task source wiring | Either GitHub Issues (label + `Depends on #N` convention) **or** a local task-list file (`refact-todo.md` style). One source of truth, chosen with the user. |
| Task source materialization | If GitHub Issues are chosen, seed them from the AGENTS.md phase plan; if local tasks are chosen, scaffold the task-list file. |
| Prompt builders | The implementation/review/fix/memory-update prompts, with this project's SOUL/AGENTS rules injected and "read the governance first" baked in. |
| Logs + ignore rules | `logs/issues/<n>/` layout and a `.gitignore` entry so pipeline logs never pollute commits or review diffs. |
| Run mode guide | A short operator guide for foreground runs and detached `tmux` runs, including a copy-pasteable long-run command. |
| Memory note | A single record in `MEMORY.md` that automation was generated, written per the governance's own update rules. |

See `references/auto-develop-template.md` for the script blueprint, `references/prompt-builders.md` for the prompts, `references/task-list-template.md` for the local task-source format, and `references/extraction-checklist.md` for the governance→script mapping.

## Governance is the contract

The four governance files are authoritative inputs. This skill consumes them and may write **only `MEMORY.md`** plus the generated automation artifacts (script, task file, logs config).

**Critical** — Do **not** edit `SOUL.md`, `AGENTS.md`, or `CLAUDE.md`. If generating the automation reveals one of them is wrong (a command does not exist, a declared model is unavailable, or the user-selected model plan differs from governance), stop and route the fix through `prd-to-governance` in Audit mode. The generated script is downstream of the governance, never a place to silently override it.

## Memory discipline is the core integration

**Critical** — The generated pipeline must implement exactly the memory-management rules that the governance defines (MEMORY.md *Update Rules* + any AGENTS.md *Auto-Develop Policy*). These are non-negotiable because they are the contract between the two skills:

- **MEMORY.md is excluded from review diffs** — generate review diffs with `git diff <base> -- . ':!MEMORY.md'` so growing status lines never bloat reviewer context across fix cycles.
- **One overwritten "Next Up" line** — the implementation/fix steps write exactly one status line to `MEMORY.md` "Next Up" (overwrite, never append).
- **Completed work goes to the archive** — only a dedicated post-review memory step writes the final one-line entry, and it writes it to `memory/completed-phases.md`, not inline in `MEMORY.md`.
- **No-op fix detection** — if a fix cycle changes only `MEMORY.md`/logs and no real code, remaining findings are accepted deviations and the review loop breaks (prevents infinite loops).
- **Dependency blocking** — `Depends on #N` (or the task-list equivalent) hard-blocks a task until its dependencies are done.

If the governance does not yet specify these, that is `[NEEDS GOVERNANCE]` — route back to the `prd-to-governance` skill ([github.com/Karlderkarl/prd-to-governance](https://github.com/Karlderkarl/prd-to-governance)), which owns the structure and update rules for `MEMORY.md` and the other governance files, rather than inventing the policy here.

## Deterministic skill resolution

**Required** — If a task should use a specific skill, that decision must be **deterministic and live in the generated script**, never left to a model turn. Otherwise "project-first" behaviour, audit logging, and reproducibility are a hope, not a property. The generated `auto-develop.sh` carries a `resolve_skill` step (see `references/auto-develop-template.md`) with these invariants:

- **Mechanism in the script.** A `SKILL_MAP` array of **explicit matchers** (`label:` / `title:` → skill) is the only decision basis. Both matchers resolve deterministically without touching the filesystem. There is **no registry, no network, and no free semantic search** as a hard decision basis.
- **Resolve once per task.** `resolve_skill` runs a single time per task (before implementation) and sets `RESOLVED_SKILL` / `RESOLVED_SKILL_REASON`.
- **Inject only where work happens.** The result is injected **only** into the implement / fix / refactor prompts. Reviewers, check-fix, and the memory step stay skill-neutral.
- **Ambiguity over guessing.** Exactly one distinct match is chosen; **more than one distinct match is `(ambiguous)` and nothing is injected** — the script never picks one. Zero matches is `(none)`.
- **Always logged.** Each decision is written to `$LOGDIR/<task>/skill-resolution.log` (`searched` / `candidates` / `chosen` / `reason`).
- **No-op default.** `SKILL_MAP=()` is fully functional — the pipeline runs unchanged with no skill policy. The policy is **preferred from governance** (AGENTS.md *Skill Policy*) but an operator may also author entries locally (e.g. from a skill's own tags/triggers/labels).

The governance source for `SKILL_MAP` is an AGENTS.md *Skill Policy* section, owned by `prd-to-governance`. That producing side is parallel work in its repo; until it exists, leave `SKILL_MAP` empty or let the user set it locally — never block generation on it.

## Two-pass pipeline: correctness, then refactor

Each task runs through **two** review-backed passes:

1. **Correctness pass** — implement → check → reviewers A/B → fix → re-review, looping until both reviewers pass (with no-op fix detection to break the loop).
2. **Refactor pass** — once correctness is approved, that state is **committed as a checkpoint**, then a second loop asks the implementation model to **simplify the code to senior-engineer quality without changing behavior** ("could this be simpler — would a senior engineer have written it this way?"). Any change it makes is **re-validated by reviewers A/B** (the same review loop). A refactor round is **kept only if its re-review comes back clean**; if reviewers object — including the case where the follow-up fix changes nothing — that round is **reverted to the checkpoint** and refactoring stops. The loop also stops once a round proposes **no change** (converged) or `MAX_REFACTOR_ROUNDS` is hit.

**Required** — The refactor pass is behavior-preserving cleanup only; it must never add features or change public behavior, and it reuses the exact same A/B review + memory discipline as the correctness pass. It runs **only after** correctness passes (which is committed first), and the user can disable it (`--no-refactor`). Two invariants make the second pass safe: (a) a not-cleanly-approved refactor **reverts to the checkpoint**, so it can never silently keep a degraded simplification and never discards the already-approved correctness work; (b) the recorded metadata reflects the real final history, since `MEMORY.md` is part of the governance contract — the commit message reports the **delivered** A/B rounds (correctness plus accepted refactor re-reviews, not discarded attempts), and the archive records correctness fixes and accepted refactor rounds as **distinct** facts (so it never implies a "last fix" that did not happen). Both passes share one `review_until_pass` implementation (which signals `clean` vs a tolerated no-op) so the review/no-op logic is never duplicated.

## Uncertainty and priority markers

Reuse `prd-to-governance`'s vocabulary so both skills agree:

- `[NEEDS GOVERNANCE]` — required governance is missing or too thin to generate from
- `[NEEDS CODEBASE DISCOVERY]` — the answer depends on inspecting the actual repository
- `[USER DECISION REQUIRED]` — a strategic/preference choice that must not be inferred (models, auto-merge, sandbox level)
- `[GOVERNANCE DRIFT]` — governance and the existing script/codebase disagree

Priority levels: **Critical** (cannot be violated without explicit approval), **Required** (default rule; deviations need explanation), **Advisory** (preferred pattern). Use them where they sharpen real stakes, not on every line.

## Modes

State the chosen mode in one line before proceeding.

- **Generate** — no automation exists yet; create `auto-develop.sh` and its supporting artifacts from the governance
- **Audit/Sync** — automation already exists; compare it against current governance, report drift, and update on approval
- **Validate** — lint/dry-run an existing or freshly generated script without running the real loop

Default selection:

- Governance missing → stop with `[NEEDS GOVERNANCE]`; recommend `prd-to-governance`
- Governance present, no `auto-develop.sh` → **Generate**
- `auto-develop.sh` already present → **Audit/Sync** first
- User says "check the script runs", "dry run" → **Validate**

## Workflow

### Step 0: Preconditions and mode

1. Determine the project root (folder with the governance files); confirm if ambiguous.
2. Confirm `SOUL.md`, `AGENTS.md`, `CLAUDE.md`, `MEMORY.md` exist. If any are missing, stop, emit `[NEEDS GOVERNANCE]`, and recommend running `prd-to-governance` first. Do not reconstruct governance here.
3. Select and state the mode.

### Step 1: Extract automation parameters from governance

Read all four files completely and extract the values the script needs. Use `references/extraction-checklist.md` as the mapping. At minimum capture:

- **Checks** (from CLAUDE.md *Development Commands*): the validation commands (type-check / lint / test / build, whatever the project uses), in order, verbatim. The script is stack-agnostic — these commands are the *only* source of the toolchain; do not assume Node, Python, or any specific runtime. Note any marked `# planned` — those are not runnable yet.
- **Roles/models** (from AGENTS.md *Roles* + CLAUDE.md): implementation model, reviewer A, reviewer B (if dual review). Treat any model the governance names as a **suggested default only** — the actual per-step model choice is always confirmed with the user in Step 3, never auto-adopted from governance.
- **Git conventions** (from AGENTS.md): base branch name, branch naming pattern, commit format, force-push/hook policy.
- **Task source**: GitHub Issues + label, or a local task-list file, or MEMORY.md "Next Up".
- **Memory paths + rules** (from MEMORY.md *Update Rules*): `MEMORY.md`, the archive path, the status-line and exclusion rules above.
- **Review focus** (from SOUL.md security/coding + AGENTS.md prohibited actions): the concise rule set to inject into review prompts.
- **Skill policy** (from AGENTS.md *Skill Policy*, if present): the explicit `label:`/`title:` → skill matchers that seed `SKILL_MAP`. **Absent is fine** — an empty `SKILL_MAP` is a valid no-op, not `[NEEDS GOVERNANCE]`. Never invent matchers.
- **Test policy** (from AGENTS.md *Auto-Develop Policy* + CLAUDE.md *Development Commands*, if present): `TEST_POLICY`, explicit `TEST_ELIGIBILITY` matchers, and `TARGETED_TEST_CMD` with a `{TARGET}` token. Entirely absent is the valid backward-compatible default (`off`), not `[NEEDS GOVERNANCE]`. But partial/contradictory fields are not: `TEST_POLICY=required` without `TARGETED_TEST_CMD` is `[GOVERNANCE DRIFT]` (the generated automation must degrade enforcement to `preferred`); `TARGETED_TEST_CMD` with policy off/absent, or a set policy with empty/inert eligibility, is `[NEEDS GOVERNANCE]`.
- **Reference docs + env vars + toolchain setup**: any PATH export, runtime activation, or `# planned` setup the project's commands need before they run, plus reference docs the agents should read. Derive these only from governance — never hardcode a default toolchain.

If a required parameter is missing, mark it `[NEEDS GOVERNANCE]` (route back) or `[USER DECISION REQUIRED]` (ask), do not guess.

### Step 2: Choose the task source

Confirm the single source of truth for what the pipeline works on:

- **GitHub Issues** — eligible issues carry a label (e.g., `agent:auto`); dependencies via `Depends on #N`. The script selects, branches, PRs, and closes them. Default for repos with a GitHub remote.
- **Local task-list file** — a `refact-todo.md`-style file with prioritized tasks/packages (see `references/task-list-template.md`). Default when there is no issue tracker; the script reads the next unchecked task.
- **MEMORY.md "Next Up"** — minimal projects only.

Do not wire two sources at once. If unclear, ask `[USER DECISION REQUIRED]`.

### Step 3: Confirm automation parameters

Present what you extracted, then confirm the choices that are strategic, not inferable. Keep it a short checklist:

1. **Models** — **Required: always ask explicitly** (`[USER DECISION REQUIRED]`), even when the governance already declares roles. Never silently inherit the model from governance. Present every build step that runs a model and let the user **freely choose** one per step:
   - **Implementation/fix model** — e.g. `opus`
   - **Reviewer A** — e.g. `sonnet`
   - **Reviewer B** (dual review only) — e.g. `codex` / `gpt-5.x`
   - plus **reasoning effort** per reviewer (e.g. `high`).

   Name these only as *examples* — any model or CLI the user names is valid; the choice is theirs. If governance already declares models, show them as the **pre-filled default** but still confirm. If the user's pick differs from what governance declares, flag `[GOVERNANCE DRIFT]` and route the correction through `prd-to-governance` (do not silently override the governance in the script).
2. **Review & refactor depth**: single review pass or dual (A/B)? Max review-fix rounds? **Refactor pass** — after the correctness review passes, run a simplification pass ("could this be simpler — would a senior engineer have written it this way?") that is re-validated by reviewers A/B? (Default: **on**.) Max refactor rounds (default 3)?
3. **Commit/merge policy**: stop at PR for human review, or auto-merge? (Default: open PR, do **not** auto-merge unless the user opts in.) "Stop at PR" is the *per-issue* terminal step — the pipeline opens the PR and does not merge it; a multi-issue batch (`--max-issues N`) still returns to the base branch and proceeds to the next eligible issue, opening one PR per issue. It does **not** halt the whole run after the first PR (that would defeat batch/detached runs). Auto-merge, when opted in, must treat a failed merge/pull as a failed issue (do not count it as completed).
4. **Execution environment**: local CLI (`claude -p`, `codex exec`) vs CI; permission/sandbox level. **Critical** — `bypassPermissions`/`danger-full-access` require explicit user opt-in (the generated script defaults to safe modes and reaches privileged ones only via `--unattended`/`--auto-merge` behind a runtime `confirm_privileged_mode` prompt; never hardcode the privileged values as defaults).
5. **Run mode**: foreground shell only, or detached long-run support as well? Default: generate a `tmux`-friendly launch path and document a command such as `./auto-develop.sh --max-issues 100` plus the detached `tmux` equivalent.
6. **Scope guards**: max issues per run, dry-run default.
7. **Skill policy**: show the resolved `SKILL_MAP` entries (or "none") for sign-off. Mark any entry that came from local operator input rather than AGENTS.md *Skill Policy*. Default is an empty map (no-op) when governance declares no policy — do not invent matchers.

### Step 4: Generate `auto-develop.sh`

From `references/auto-develop-template.md`, produce the project's script:

- Fill in checks, the explicitly confirmed model/runner mapping, base branch, label/task-source, memory paths, reference docs, PATH/toolchain.
- Build the prompt functions from `references/prompt-builders.md`, injecting the SOUL/AGENTS rules and always instructing agents to read `SOUL.md`/`AGENTS.md`/`MEMORY.md` first (single source of truth — do not duplicate large governance text into the script).
- Wire every memory rule from the *Memory discipline* section above. This is the part most likely to be done wrong; verify each rule is present.
- Wire the *Deterministic skill resolution* step: fill `SKILL_MAP` from the AGENTS.md *Skill Policy* plus any explicitly user-approved local entries (empty array only if both are absent), keep the `resolve_skill` function and its one-per-task call before implementation, and inject `RESOLVED_SKILL` only into the implement/fix/refactor prompts. Confirm the decision is logged to `skill-resolution.log`.
- Wire the optional **test-discipline** contract when governance declares it: emit `TEST_POLICY`, `TEST_ELIGIBILITY`, and `TARGETED_TEST_CMD` into the script; resolve task eligibility once per task with the same explicit `label:` / `title:` matcher discipline (no heuristic "this probably needed tests"); treat absent fields as the valid `off` default; degrade `required` to `preferred` with a logged `[GOVERNANCE DRIFT]` when no targeted test command exists; and make the gate deterministic by having the implementation/fix flow surface one concrete `{TARGET}` for the script to run.
- Keep the proven control flow: clean-worktree guard, dependency check, branch management (branch each issue **from the base branch** and return to it after the PR, so a `--max-issues > 1` run never stacks issue N on issue N-1's unmerged tip), checks-with-autofix, correctness review loop with no-op detection, a checkpoint commit **gated on a non-empty code diff** (a memory-only change must not produce an "implemented" commit), refactor stage (simplify → re-check → re-review) with no-op/round guards, memory-update step, commit/PR (and merge only if opted in). On any failure path, roll back by **discarding** in-progress work and returning to the base branch — never a bare `git checkout` that could carry half-written changes onto it.
- Factor the A/B review + fix loop into one `review_until_pass` function reused by both the correctness pass and the refactor re-validation; gate the refactor stage on `REFACTOR`/`--no-refactor` and bound it with `MAX_REFACTOR_ROUNDS`. Add `build_refactor_prompt` from `references/prompt-builders.md` — behavior-preserving simplification only, with the "make no change if already clean" instruction that drives convergence.

### Step 5: Generate supporting artifacts

- **Task source**: materialize the backlog from the AGENTS.md *Phase Plan* — one entry per phase sub-task — into the chosen source.
  - **If local**: scaffold the task-list file from `references/task-list-template.md`, seeded from the phase plan.
  - **If GitHub Issues**: emit the `gh label create` command, then **seed the issues** with a `gh issue create` per phase sub-task — each carrying the task label and a `Depends on #N` line encoding the phase order (see `references/task-list-template.md` Option A for the exact commands). **Creating issues is an outward-facing action**: present the planned issue titles/bodies/dependencies and get explicit approval before running any `gh issue create`; never create them silently. Keep a short convention note (label + `Depends on #N`) alongside.
- **Logs + ignore**: ensure `logs/` is gitignored (and that `memory/completed-phases.md` is **not** accidentally ignored — use a precise pattern).
- **Usage**: a brief run guide covering the script's own `--help`, the eligibility/dependency convention, direct runs such as `./auto-develop.sh --max-issues 100`, and detached `tmux` runs such as `tmux new-session -d -s auto-develop './auto-develop.sh --max-issues 100'`.

### Step 6: Validate

- Syntax-check the script (`bash -n auto-develop.sh`; `shellcheck` if available) and report results honestly.
- Run it with `--dry-run` to confirm candidate selection works without executing models, if the environment allows.
- Make it executable (`chmod +x`). Never run the real loop as part of generation.

### Step 7: Present, confirm, record

1. Summarize the generated artifacts and every value you chose that was not explicit in the governance.
2. List any `[NEEDS GOVERNANCE]`, `[USER DECISION REQUIRED]`, or `[GOVERNANCE DRIFT]` items.
3. Ask for approval before writing files; in Audit/Sync mode, show the drift and proposed diffs first.
4. After writing, record a single line in `MEMORY.md` per its update rules (e.g., "Auto-develop pipeline generated") — detail goes to `memory/completed-phases.md`. Do not commit; let the user review.

### Audit/Sync mode

Do not rewrite blindly. Read the existing script, re-extract parameters from current governance, and report mismatches in four buckets, tagging significant ones `[GOVERNANCE DRIFT]`:

- **Stale checks** — script runs commands that no longer exist in CLAUDE.md (or misses new ones)
- **Role/model drift** — script roles, runners, or model selections differ from AGENTS.md/CLAUDE.md expectations
- **Memory-rule drift** — script no longer matches MEMORY.md update rules (diff exclusion, status-line, archive ownership, no-op detection)
- **Convention drift** — base branch, label, commit format, or dependency handling diverged
- **Skill-policy drift** — `SKILL_MAP` no longer matches the AGENTS.md *Skill Policy* plus explicitly user-approved local entries (stale/missing matchers, entries with neither a policy nor a user-approval source, or overlapping rules that now resolve to `(ambiguous)`)
- **Test-policy drift** — the script's `TEST_POLICY`, `TEST_ELIGIBILITY`, or targeted-test gate no longer matches AGENTS.md *Auto-Develop Policy* / CLAUDE.md `TARGETED_TEST_CMD`

Also report these governance contract gaps explicitly:

- `[GOVERNANCE DRIFT]` when AGENTS.md sets `TEST_POLICY=required` but CLAUDE.md declares no `TARGETED_TEST_CMD` (deterministic gate unavailable → degrade to `preferred`)
- `[NEEDS GOVERNANCE]` when test fields are partial or contradictory: `TARGETED_TEST_CMD` exists while `TEST_POLICY` is off/absent, or `TEST_POLICY` is set but `TEST_ELIGIBILITY` is empty/inert. Test fields entirely absent are the valid default (`off`), not drift.

Present findings, then update only the approved parts.

## Adaptation guidelines

- **Solo / small project?** Single review pass (or "user reviews"); drop Reviewer B from the script.
- **No GitHub tracker?** Use the local task-list source; skip `gh` issue/PR steps and stop after commit on a branch.
- **GitHub tracker?** Do not stop at label creation; materialize the backlog into actual issues from the AGENTS.md phase plan, with dependencies encoded in the body.
- **No CI?** Generate a local-CLI script; do not assume a runner.
- **Long unattended run?** Generate explicit `tmux` launch guidance or an in-script detached mode so the operator can safely run long batches such as `./auto-develop.sh --max-issues 100`.
- **Refactor pass not wanted?** It is on by default; generate the `--no-refactor` flag (and `--max-refactor-rounds`) so the operator can skip or bound the simplification pass. For cost-sensitive or trivial-change projects, defaulting it off is a valid choice — confirm in Step 3.
- **Any stack?** The script never assumes one. Whatever CLAUDE.md lists as validation commands (npm/pnpm, uv/poetry, cargo, go, make, gradle, or none) becomes the check list as-is; the toolchain-setup line carries only what governance specifies.
- **No skill policy?** `SKILL_MAP=()` is a valid no-op — the pipeline runs unchanged. Do not invent matchers; let the user add local entries if they want skill resolution before AGENTS.md *Skill Policy* exists.
- **Governance thin or missing?** Stop and route to `prd-to-governance`; never invent the contract here.
- **Security-sensitive project?** Keep the SOUL.md prohibitions in the review prompt and require explicit opt-in for any bypass/sandbox flags.

## Quality checklist

Before presenting:

- [ ] Mode stated (`Generate` / `Audit-Sync` / `Validate`)
- [ ] All four governance files read; missing ones blocked the run with `[NEEDS GOVERNANCE]`
- [ ] Checks, base branch, and task source were extracted from governance, not guessed
- [ ] Models were **explicitly chosen by the user** per step (impl / reviewer A / reviewer B + effort), not silently inherited from governance; any divergence from governance flagged as `[GOVERNANCE DRIFT]`
- [ ] Exactly one task source is wired
- [ ] Each issue branches **from the base branch** (not the current HEAD) and the run returns to the base branch after each issue, so a `--max-issues > 1` run never stacks branches; failure paths discard work before returning, never a bare `git checkout`
- [ ] The correctness checkpoint commit is gated on a **non-empty code diff** (excluding `MEMORY.md`/logs), so a memory-only model run cannot produce an empty "implemented" commit + PR
- [ ] The backlog was **materialized** from the AGENTS.md Phase Plan into that source (task-list scaffolded, or issues seeded via `gh issue create` after explicit approval) — not merely documented as a convention
- [ ] The generated usage covers detached long runs (`tmux` or equivalent) when the user asked for unattended execution
- [ ] Every memory-discipline rule is present in the generated script (diff exclusion, single Next Up line, archive-only completed work, no-op detection, dependency blocking)
- [ ] Skill resolution is deterministic: `SKILL_MAP` came from AGENTS.md *Skill Policy* or from explicitly user-approved local entries (or is an empty no-op) — never silently invented; `resolve_skill` runs once per task and logs `searched`/`candidates`/`chosen`/`reason`, `(ambiguous)` injects nothing, and the result is injected only into the implement/fix/refactor prompts
- [ ] Test policy is wired for the **chosen task source, not just GitHub issues**: `resolve_test_policy`, the per-task reset of all test state (`TARGETED_TEST_FILE`, `FROZEN_TARGETED_TEST_TARGET`, `TEST_GATE_ACTIVE`), and the RED-before-GREEN sub-phase appear in the generated script regardless of source. `FROZEN_TARGETED_TEST_TARGET=""` **must** be reset at the top of every task in every variant — a multi-task run (task-list especially) would otherwise freeze task N's RED-confirmed target into task N+1's GREEN reruns. In the local task-list / MEMORY.md variants (no labels) only `title:` matchers can make a task eligible — a `label:`-based `TEST_ELIGIBILITY` there is flagged `[GOVERNANCE DRIFT]`, never silently denylist-enabling every task
- [ ] Test policy is deterministic and opt-in: absent/empty fields default to `off`; `TEST_ELIGIBILITY` uses explicit `label:` / `title:` include/except matchers only, resolved once per task with **`except` winning over `include`** and a declared-include base default (no "ambiguous" outcome); only **well-formed** matchers drive the base default, and a set that is empty **or has no usable matcher** (dead types/regexes) is inert → `off` **and warned** — never falling through to "test every task"
- [ ] The gate proves a **red→green transition** (not a green-only smoke test), with honest scope: the test-first sub-phase requires a NON-ZERO `expect_red` result **before** implementation and reruns the same target after implementation; a tautological always-green test is rejected, and the RED-confirmed target is frozen for the rest of the task so later prompts cannot retarget the proof. But a non-zero exit is **not exit-verified** to be an assertion failure vs a syntax/import/collection error (stack-agnostic — no framework exit-code parsing); the "right reason" is carried by the test-authoring prompt, and must not be described as exit-verified. The **hard** green gate (`TEST_GATE_ACTIVE` → enforced by `ensure_checks_pass`) is armed **only under `required`**: there an unprovable RED fails the issue and a still-red target blocks. Under `preferred` the post-impl rerun is still executed, but an unresolved failure remains **advisory**; `preferred` must never hard-block, discard correctness work, or trigger extra code mutation when ordinary checks are already green — otherwise it has collapsed into `required`
- [ ] The model-authored `{TARGET}` is **sanitized** (test-id/path characters only) before substitution into the `eval`'d targeted command
- [ ] The gate's scope is stated honestly: it is a **targeted TDD gate, not a full no-regression gate** — it proves only the one designated test red→green; broad regression coverage is only whatever `CHECKS[]` already runs. The known limitation (a pre-existing red full suite in `CHECKS[]` blocks the pipeline; no general "nothing else regressed" proof) is documented, not implied away. A general no-regression baseline (capture `CHECKS[]` state only when green pre-task, else disable the compare and log) is explicitly **out of scope for v1**
- [ ] Review enforces the policy asymmetrically: `required` missing-tests block (numbered finding); `preferred` missing-tests use the non-blocking `ADVISORY:` channel so `preferred` never collapses into `required`
- [ ] If AGENTS.md sets `TEST_POLICY=required`, CLAUDE.md provides a `TARGETED_TEST_CMD` with a `{TARGET}` token; otherwise the generated automation degrades to `preferred` and surfaces `[GOVERNANCE DRIFT]` instead of silently pretending the hard gate exists
- [ ] The refactor pass (unless `--no-refactor`) runs only after the correctness state is committed as a checkpoint, re-validates through A/B via the shared `review_until_pass`, **keeps a round only on a clean re-review** (reverts to the checkpoint otherwise — degraded refactors are never kept and correctness work is never lost), is behavior-preserving only, and is bounded by no-op detection + `MAX_REFACTOR_ROUNDS`
- [ ] Metadata reflects the real history, not a pre-refactor snapshot: commit reports the delivered A/B rounds (correctness plus accepted refactor re-reviews, not discarded refactor attempts), and the memory archive gates "last fix" on correctness fix rounds and the simplification note on `REFACTOR_ROUNDS` (the two are not conflated)
- [ ] `SOUL.md`, `AGENTS.md`, `CLAUDE.md` were **not** edited; only `MEMORY.md` + automation artifacts changed
- [ ] Prompts instruct agents to read the governance and do not duplicate large governance text
- [ ] Privileged/sandbox flags (`bypassPermissions`, `danger-full-access`, auto-merge) are **off by default** and reached only via `--unattended`/`--auto-merge` behind the runtime `confirm_privileged_mode` gate (skipped by `--dry-run`/`--yes`, refuses without a TTY); never hardcoded as defaults, and the tmux re-exec propagates the opt-in plus `--yes`
- [ ] Script passed `bash -n` (and `shellcheck` if available); `--dry-run` was offered
- [ ] `logs/` is ignored and `memory/completed-phases.md` is not accidentally ignored
- [ ] Any governance mismatch was marked `[GOVERNANCE DRIFT]` and routed to `prd-to-governance`, not patched into the script
