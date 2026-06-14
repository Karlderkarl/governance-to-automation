# Prompt Builders

Blueprints for the prompt functions the generated `auto-develop.sh` writes to temp files and pipes to the model CLIs. Each prompt is built from governance — but **link, don't duplicate**: instruct agents to read `SOUL.md` / `AGENTS.md` / `MEMORY.md` (single source of truth) and inject only a *concise* extract where inline context genuinely helps the reviewer.

## Design principle: link vs inline

- **Implementation / fix / memory prompts** → instruct the agent to read the governance files. The agent runs inside the repo, so it can. Keep these prompts short.
- **Review prompts** → reviewers benefit from a compact, inline `{{GOVERNANCE_REVIEW_FOCUS}}` (the highest-stakes SOUL.md security/coding rules + AGENTS.md prohibited actions). Extract ~8-15 bullet points; do not paste whole files. Regenerate this extract whenever governance changes (Audit/Sync mode).

## 1. build_implementation_prompt(issue, title, body, outfile)

```text
You are implementing issue #<issue> for <PROJECT_NAME>.

## Issue
**#<issue>: <title>**
<body>

<!-- Render ONLY when RESOLVED_SKILL is a real skill (not "(none)"/"(ambiguous)"): -->
## Designated skill
This task resolves to the `<RESOLVED_SKILL>` skill (reason: <RESOLVED_SKILL_REASON>). Use it for this work.

## Instructions
- Read SOUL.md, AGENTS.md and MEMORY.md before starting. Read <REFERENCE_DOCS> if relevant.
- Implement in small, testable steps, following the coding standards in SOUL.md and the prohibited actions in AGENTS.md.
- Do NOT modify SOUL.md, AGENTS.md, or CLAUDE.md.
- In MEMORY.md "Next Up", set (overwrite, do not append) ONE status line: `- #<issue> (<title>): implementing`
- Do NOT write to "Completed Work" — the pipeline handles that after review.
- Save all files. Do NOT commit — the pipeline handles that.
```

The `## Designated skill` block is emitted by the script **only** when `resolve_skill` chose exactly one skill. For `(none)` or `(ambiguous)` the block is omitted entirely — the script never picks a skill for the agent to guess at.

## 2. build_review_prompt(label, issue, title, body, diff, outfile)

```text
You are <label> reviewing implementation for issue #<issue>.

## Issue
**#<issue>: <title>**
<body>

## Project rules (authoritative: SOUL.md / AGENTS.md)
<{{GOVERNANCE_REVIEW_FOCUS}} — concise extract, e.g.:>
- <stack + architecture invariant>
- <security principle, e.g. encrypt X at rest; validate+rate-limit public POST>
- <coding standard, e.g. strict types, named exports>
- <prohibited action, e.g. no privileged data access in client code>

## Role focus
<Reviewer A: correctness, security, architecture, type quality>
<Reviewer B: issue coverage, regressions, edge cases, file hygiene>

## Diff to review
```diff
<diff>
```

## Rules
- READ-ONLY review. Do NOT edit files.
- Flag only real issues; don't nitpick what linters handle.
- If incomplete or unclear, reject — do not silently accept.

## Output
- If good: respond with exactly `LGTM`.
- Else a numbered list: `N. [CRITICAL|HIGH|MEDIUM|LOW] file:line - description`
- End with: `FINDINGS: <count>`
```

The script treats a leading `LGTM` as a pass (`grep -qi "^LGTM"`). Keep that contract.

## 3. build_fix_prompt(issue, title, body, findings_a, findings_b, round, outfile)

```text
You are fixing review findings for issue #<issue>.

## Issue
**#<issue>: <title>**
<body>

## Reviewer A findings
<contents of findings_a>

## Reviewer B findings
<contents of findings_b, or "(none)" for single-review projects>

<!-- Render ONLY when RESOLVED_SKILL is a real skill (same rule as the implementation prompt): -->
## Designated skill
This task resolves to the `<RESOLVED_SKILL>` skill (reason: <RESOLVED_SKILL_REASON>). Use it for this work.

## Instructions
- Address all CRITICAL and HIGH; address MEDIUM if straightforward.
- Read SOUL.md and AGENTS.md for standards and prohibited actions. Do NOT modify SOUL.md, AGENTS.md, or CLAUDE.md.
- In MEMORY.md "Next Up", OVERWRITE the status line for this issue with:
  `- #<issue>: review round <round>, fixing: <brief>`
- Do NOT append, and do NOT touch "Completed Work".
- Save files. Do NOT commit.
```

The overwrite-one-line rule is what enables no-op fix detection in the script. Keep it explicit.

## 4. build_refactor_prompt(issue, title, body, round, outfile)

The second pass. The code already passes review and all checks — this prompt asks for behavior-preserving simplification to senior-engineer quality, nothing more.

```text
You are refactoring the already-approved implementation of issue #<issue> for <PROJECT_NAME>.

The code already passes review and all checks. Your ONLY job is to make it
simpler and cleaner WITHOUT changing behavior.

## Issue
**#<issue>: <title>**
<body>

<!-- Render ONLY when RESOLVED_SKILL is a real skill (same rule as the implementation prompt): -->
## Designated skill
This task resolves to the `<RESOLVED_SKILL>` skill (reason: <RESOLVED_SKILL_REASON>). Use it for this simplification.

## Ask — go file by file over the change and ask:
- Would a senior engineer have written it this way?
- Can it be simpler — less duplication, clearer names, fewer moving parts, better
  reuse of existing helpers/abstractions, more idiomatic for the language/stack?
- Does it match the patterns and standards in SOUL.md / AGENTS.md?

Apply ONLY behavior-preserving simplifications. Do NOT add features, change public
behavior, or expand scope. If the code is already clean and a senior engineer would
sign off as-is, make NO changes at all.

## Instructions
- Read SOUL.md (and AGENTS.md) for standards first. Do NOT modify SOUL.md, AGENTS.md, or CLAUDE.md.
- Keep every existing check passing.
- In MEMORY.md "Next Up", OVERWRITE the status line for this issue with:
  `- #<issue>: refactor round <round>, simplifying: <brief or "no change needed">`
- Do NOT append, and do NOT touch "Completed Work".
- Save files. Do NOT commit.
```

**Making no change when the code is already clean is the contract** — that is what lets the script detect convergence (the `md5sum` of the code diff is unchanged) and stop the refactor loop. Keep the "make NO changes" instruction explicit, and keep the MEMORY.md line excluded from the no-op comparison (the script already excludes `{{MEMORY_FILE}}`).

## 5. build_memory_update_prompt(issue, title, fix_rounds, refactor_rounds, outfile)

This is the only step allowed to record completed work — and it writes to the archive, per the governance memory rules. The two count arguments are **distinct** and must not be conflated: `fix_rounds` is the correctness-pass review count (so `> 1` means at least one *fix* actually happened), and `refactor_rounds` is how many refactor rounds were *accepted* (`> 0` means the refactor pass changed code). A task can have several delivered review rounds purely from accepted refactor re-reviews **without** any "last fix" — keep the two gates separate so the archive line never implies a fix that did not occur.

```text
Update memory for completed issue #<issue>.

1. Add a ONE-LINE entry to `<ARCHIVE_FILE>` under the right phase heading.
2. Remove any "Next Up" status line for #<issue> in MEMORY.md.
3. Do NOT add issue detail to MEMORY.md — only update Next Up and blockers there.

Format: `- <title> (#<issue>): <brief what was built>[. Last fix: <final fix>][. Simplified in <refactor_rounds> refactor round(s)]`
- Include "Last fix: …" ONLY if <fix_rounds> > 1 (a correctness fix actually happened).
- Include "Simplified in …" ONLY if <refactor_rounds> > 0 (the refactor pass changed code).

Rules:
- Read MEMORY.md's Update Rules first; MEMORY.md stays lean.
- 1-2 lines max. Don't document review cycles or reviewer names.
- Do NOT modify SOUL.md, AGENTS.md, or CLAUDE.md.
- Do NOT commit — the pipeline folds these memory edits into the one issue commit.
```

## 6. build_check_fix_prompt(issue, check_output, outfile)

```text
The implementation for issue #<issue> has failing checks. Fix them.

## Check output
<check_output>

## Instructions
- Fix the failing checks (<list the CHECK_CMDS>).
- Read SOUL.md and AGENTS.md for coding standards and prohibited actions. Do NOT modify SOUL.md, AGENTS.md, or CLAUDE.md.
- Do NOT commit.
```

## Generation rules

- Always include "Do NOT modify SOUL.md, AGENTS.md, or CLAUDE.md" and "Do NOT commit" in **every** write-capable prompt — these enforce the skill boundaries inside the autonomous loop (the pipeline writes only `MEMORY.md` + generated artifacts; all three governance files are off-limits, corrections route back through `prd-to-governance`). The memory-update prompt counts: it writes `MEMORY.md`/the archive, and the pipeline owns the commit (it amends the issue commit right after), so a stray agent commit would corrupt that flow.
- The four **code-writing** prompts (implement, fix, check-fix, refactor) must instruct the agent to **read SOUL.md and AGENTS.md** first — SOUL.md carries the coding standards, AGENTS.md the prohibited actions and role boundaries. Omitting AGENTS.md lets the agent miss those constraints (see SKILL.md Step 4). The memory-update prompt is skill-neutral and instead reads **MEMORY.md's Update Rules** (it touches only memory, not code).
- The `## Designated skill` block goes **only** into the implementation, fix, and refactor prompts, and only when `resolve_skill` chose exactly one skill (`RESOLVED_SKILL` is real). The review, check-fix, and memory-update prompts must stay skill-neutral — reviewers judge against governance, not a designated skill.
- Always include the single-status-line / overwrite / archive rules verbatim from the governance memory policy.
- Keep `{{GOVERNANCE_REVIEW_FOCUS}}` short and regenerate it on Audit/Sync so reviewers never enforce stale rules.
- Use heredocs to write prompts to temp files; never pass large prompts as CLI args.
