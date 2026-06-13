---
name: governance-to-automation
description: "Generate (and keep in sync) the automation that executes a project's governance. From the governance files (SOUL.md, AGENTS.md, CLAUDE.md, MEMORY.md) this skill produces a project-tailored, stack-agnostic issue-driven auto-develop pipeline script plus its task source, prompt builders, and logging — wired to the exact memory-management discipline that prd-to-governance defines. Use after governance exists and the user wants the build loop automated."
license: MIT
---

# Governance to Automation

This skill **generates the automation** that runs a project end to end. It is the execution counterpart to `prd-to-governance`:

- `prd-to-governance` is the **blueprint for splitting the project into files** (`SOUL.md`, `AGENTS.md`, `CLAUDE.md`, `MEMORY.md`) and it defines **how and where memory is managed** (what goes into `MEMORY.md` vs `memory/completed-phases.md`, the status-line discipline, drift handling).
- `governance-to-automation` reads that governance and **emits the runnable pipeline** — primarily an `auto-develop.sh` script that processes tasks autonomously: implement → check → review → fix → commit → PR. The script *embodies* the memory rules the governance prescribes.

The skill does **not** itself implement features. It writes the machinery that does, configured to one specific project's contract.

For this skill, one project equals one folder. The project root is the folder that contains the governance files. Read and write only inside it unless the user says otherwise.

## What this skill produces

| Artifact | Purpose |
|---|---|
| `auto-develop.sh` | The pipeline. Selects eligible tasks, runs implement/check/review/fix loop, commits, opens PR, updates memory. Parameterized to this project. |
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

If the governance does not yet specify these, that is `[NEEDS GOVERNANCE]` — route back to `prd-to-governance` rather than inventing the policy here.

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
2. **Review depth**: single pass or dual (A/B)? Max review-fix rounds?
3. **Commit/merge policy**: stop at PR for human review, or auto-merge? (Default: open PR, do **not** auto-merge unless the user opts in.)
4. **Execution environment**: local CLI (`claude -p`, `codex exec`) vs CI; permission/sandbox level. **Critical** — `bypassPermissions`/`danger-full-access` require explicit user opt-in.
5. **Run mode**: foreground shell only, or detached long-run support as well? Default: generate a `tmux`-friendly launch path and document a command such as `./auto-develop.sh --max-issues 100` plus the detached `tmux` equivalent.
6. **Scope guards**: max issues per run, dry-run default.

### Step 4: Generate `auto-develop.sh`

From `references/auto-develop-template.md`, produce the project's script:

- Fill in checks, the explicitly confirmed model/runner mapping, base branch, label/task-source, memory paths, reference docs, PATH/toolchain.
- Build the prompt functions from `references/prompt-builders.md`, injecting the SOUL/AGENTS rules and always instructing agents to read `SOUL.md`/`AGENTS.md`/`MEMORY.md` first (single source of truth — do not duplicate large governance text into the script).
- Wire every memory rule from the *Memory discipline* section above. This is the part most likely to be done wrong; verify each rule is present.
- Keep the proven control flow: clean-worktree guard, dependency check, branch management, checks-with-autofix, review loop with no-op detection, memory-update step, commit/PR (and merge only if opted in).

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

Present findings, then update only the approved parts.

## Adaptation guidelines

- **Solo / small project?** Single review pass (or "user reviews"); drop Reviewer B from the script.
- **No GitHub tracker?** Use the local task-list source; skip `gh` issue/PR steps and stop after commit on a branch.
- **GitHub tracker?** Do not stop at label creation; materialize the backlog into actual issues from the AGENTS.md phase plan, with dependencies encoded in the body.
- **No CI?** Generate a local-CLI script; do not assume a runner.
- **Long unattended run?** Generate explicit `tmux` launch guidance or an in-script detached mode so the operator can safely run long batches such as `./auto-develop.sh --max-issues 100`.
- **Any stack?** The script never assumes one. Whatever CLAUDE.md lists as validation commands (npm/pnpm, uv/poetry, cargo, go, make, gradle, or none) becomes the check list as-is; the toolchain-setup line carries only what governance specifies.
- **Governance thin or missing?** Stop and route to `prd-to-governance`; never invent the contract here.
- **Security-sensitive project?** Keep the SOUL.md prohibitions in the review prompt and require explicit opt-in for any bypass/sandbox flags.

## Quality checklist

Before presenting:

- [ ] Mode stated (`Generate` / `Audit-Sync` / `Validate`)
- [ ] All four governance files read; missing ones blocked the run with `[NEEDS GOVERNANCE]`
- [ ] Checks, base branch, and task source were extracted from governance, not guessed
- [ ] Models were **explicitly chosen by the user** per step (impl / reviewer A / reviewer B + effort), not silently inherited from governance; any divergence from governance flagged as `[GOVERNANCE DRIFT]`
- [ ] Exactly one task source is wired
- [ ] The backlog was **materialized** from the AGENTS.md Phase Plan into that source (task-list scaffolded, or issues seeded via `gh issue create` after explicit approval) — not merely documented as a convention
- [ ] The generated usage covers detached long runs (`tmux` or equivalent) when the user asked for unattended execution
- [ ] Every memory-discipline rule is present in the generated script (diff exclusion, single Next Up line, archive-only completed work, no-op detection, dependency blocking)
- [ ] `SOUL.md`, `AGENTS.md`, `CLAUDE.md` were **not** edited; only `MEMORY.md` + automation artifacts changed
- [ ] Prompts instruct agents to read the governance and do not duplicate large governance text
- [ ] Privileged/sandbox flags (`bypassPermissions`, `danger-full-access`, auto-merge) were used only with explicit user opt-in
- [ ] Script passed `bash -n` (and `shellcheck` if available); `--dry-run` was offered
- [ ] `logs/` is ignored and `memory/completed-phases.md` is not accidentally ignored
- [ ] Any governance mismatch was marked `[GOVERNANCE DRIFT]` and routed to `prd-to-governance`, not patched into the script
