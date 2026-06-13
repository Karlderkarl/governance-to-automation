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

Seed issues from the AGENTS.md *Phase Plan*: one issue per phase sub-task, with `Depends on #N` encoding the order.

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
- After review passes, the memory step flips `status: open → done` (and archives the completed line) — the task-list file is the local analogue of "closing the issue".
- A task with unmet dependencies is skipped silently, exactly like `Depends on #N`.

## Option C — MEMORY.md "Next Up" (minimal projects only)

For very small projects, the script can read the single top item from MEMORY.md "Next Up". No labels, no PRs — implement, check, review, commit on a branch, advance the line. Use only when neither issues nor a task-list file is warranted.

## Guidelines

- Never wire two sources at once — pick A, B, or C with the user (`[USER DECISION REQUIRED]` if unclear).
- Keep dependency semantics identical across sources: a blocked task is skipped, not failed.
- The task source defines *what* to build; the governance defines *how*. Do not let the task file restate coding standards or security rules — those live in SOUL.md/AGENTS.md.
