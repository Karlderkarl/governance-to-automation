# Task Source Template

The pipeline needs exactly one source of truth for what to work on. Choose one; wire only that one.

## Option A — GitHub Issues (default when a GitHub remote exists)

Convention the generated script relies on:

- **Eligibility**: issues carry a label (e.g., `agent:auto`). Create it once:
  ```bash
  gh label create agent:auto --description "Processed by auto-develop.sh" --color FBCA04
  ```
- **Dependencies**: put `Depends on #N` in the issue body. The script blocks the issue until every referenced issue is `CLOSED`.
- **Lifecycle**: the script branches `issue-<n>-<slug>`, implements, reviews, commits, opens a PR with `Closes #<n>`, and (only if opted in) merges.
- **Granularity**: one issue = one shippable unit, small enough for a meaningful single review.

**Seeding the backlog** — create one issue per phase sub-task from the AGENTS.md *Phase Plan*, with `Depends on #N` encoding the order. This is an outward-facing action: present the planned titles/bodies/dependencies and get explicit approval first, then run (per sub-task):

```bash
gh issue create \
  --title "<phase sub-task title>" \
  --label agent:auto \
  --body $'<one-line goal>\n\nDepends on #<N>'   # omit the Depends line if none
```

Concrete example:

```bash
gh issue create \
  --title "Phase 1 - foundation bootstrap" \
  --label agent:auto \
  --body $'Source: AGENTS.md Phase Plan\n\nGoal:\n- Bootstrap the repository foundation\n\nDepends on: none'

gh issue create \
  --title "Phase 2 - workflow automation" \
  --label agent:auto \
  --body $'Source: AGENTS.md Phase Plan\n\nGoal:\n- Add the automated workflow layer\n\nDepends on #1'
```

Because dependencies reference issue numbers that only exist after creation, seed in dependency order (roots first) and fill in each `Depends on #N` once the referenced issue number is known — or create the issues first, then `gh issue edit <n> --body` to add the `Depends on #N` lines. Capture the created numbers as you go.

## Option B — Local task-list file (default when there is no issue tracker)

A `refact-todo.md`-style file the script reads top-down for the next unchecked task. Blueprint:

```markdown
# <Project> Task List

## Priority 1

### 1. <Task title>
<one-line goal>
- depends on: <none | #2>
- status: open        <!-- open | doing | done -->

### 2. <Task title>
<one-line goal>
- depends on: none
- status: open

## Priority 2

### 3. <Task title>
- depends on: 1
- status: open

## Packages

| Package | Tasks | Effort |
|---|---|---|
| Minimal clean | 1-2 | 1-2 h |
| Sensible block | 1-3 | 4-6 h |
| Full pass | 1-N | 6-8 h |

## Post-package checks
After each package, run the project checks:
- `<check cmd 1>`
- `<check cmd 2>`
- quick visual check of the touched files/routes
```

How the script consumes it (replacing the `gh` selection in the template):

- Pick the first task whose `status: open` and whose `depends on` tasks are all `done`.
- Derive the branch from the task number/title.
- For skill resolution, call `resolve_skill` with an empty label string (a task-list task has no labels), so only `title:` matchers in the AGENTS.md *Skill Policy* can resolve a skill in this variant.
- **Wire the test-discipline contract identically to the issue variant** (it is task-source-general, not issue-only): call `resolve_test_policy` with an empty label string and **reset the full per-task test state at the top of every task exactly as the issue flow does** — `TARGETED_TEST_FILE` (set + `rm -f`), `FROZEN_TARGETED_TEST_TARGET=""`, and `TEST_GATE_ACTIVE=false` — then run the test-first **RED-before-GREEN** sub-phase before implementation when the task is test-eligible and a `TARGETED_TEST_CMD` exists. Resetting `FROZEN_TARGETED_TEST_TARGET` per task is **not optional**: a task-list run reuses the same process for many tasks in one invocation, so a RED-confirmed target left over from task N would otherwise be frozen into task N+1's GREEN reruns and "prove" a transition that never happened for that task. The same precedence and fail-safe rules carry through unchanged (`except` wins; allowlist/denylist base by declared usable matchers; inert sets → `off`). Without this, test policy is documented but not actually generable for repos with no issue tracker.
  - **`label:` `TEST_ELIGIBILITY` matchers can never match here** (a task-list task has no labels), exactly like skill resolution — so only `title:` matchers make a task test-eligible. A `label:`-only **`except`** set is a footgun in this variant: every label match fails, so the resolver falls to the denylist base and switches testing on for *every* task. The runtime cannot detect this (it cannot know the source has no labels), so flag a `label:`-based `TEST_ELIGIBILITY` against a task-list source as `[GOVERNANCE DRIFT]` at generation/audit time and require `title:` matchers instead.
- After review passes, the memory step flips `status: open → done` (and archives the completed line) — the task-list file is the local analogue of "closing the issue".
- A task with unmet dependencies is skipped silently, exactly like `Depends on #N`.
- **`--dry-run` must stay read-only**: print the task it *would* run, but do **not** flip `status` or otherwise write the task file. A dry-run that dirties `refact-todo.md` would trip the next real run's clean-worktree guard. Guard the status flip behind the dry-run check.

## Option C — MEMORY.md "Next Up" (minimal projects only)

For very small projects, the script can read the single top item from MEMORY.md "Next Up". No labels, no PRs — implement, check, review, commit on a branch, advance the line. Use only when neither issues nor a task-list file is warranted.

- **Test discipline carries identically here too** (it is task-source-general, never issue-only): if governance opted in, wire `resolve_test_policy` with an empty label string, the **full per-task reset** of `TARGETED_TEST_FILE` / `FROZEN_TARGETED_TEST_TARGET` / `TEST_GATE_ACTIVE`, and the RED-before-GREEN sub-phase — exactly as Option B above spells out (and as SKILL.md / `extraction-checklist.md` require for *any* source). Like the task-list variant, a MEMORY.md "Next Up" item has **no labels**, so only `title:` `TEST_ELIGIBILITY` matchers can make it test-eligible; flag a `label:`-based `TEST_ELIGIBILITY` against this source as `[GOVERNANCE DRIFT]`. Where test policy is `off` (the default for minimal projects), none of this emits — the minimal flow above is the whole script.

## Guidelines

- Never wire two sources at once — pick A, B, or C with the user (`[USER DECISION REQUIRED]` if unclear).
- Keep dependency semantics identical across sources: a blocked task is skipped, not failed.
- The task source defines *what* to build; the governance defines *how*. Do not let the task file restate coding standards or security rules — those live in SOUL.md/AGENTS.md.
- In GitHub-issue mode, "seed the backlog" means actual `gh issue create` commands, not just creating the label.
