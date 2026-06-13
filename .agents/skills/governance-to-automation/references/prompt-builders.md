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

## Instructions
- Read SOUL.md and MEMORY.md before starting. Read <REFERENCE_DOCS> if relevant.
- Implement in small, testable steps, following the coding standards in SOUL.md.
- Do NOT modify SOUL.md or AGENTS.md.
- In MEMORY.md "Next Up", add ONE status line: `- #<issue> (<title>): implementing`
- Do NOT write to "Completed Work" — the pipeline handles that after review.
- Save all files. Do NOT commit — the pipeline handles that.
```

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

## Instructions
- Address all CRITICAL and HIGH; address MEDIUM if straightforward.
- Read SOUL.md for standards. Do NOT modify SOUL.md or AGENTS.md.
- In MEMORY.md "Next Up", OVERWRITE the status line for this issue with:
  `- #<issue>: review round <round>, fixing: <brief>`
- Do NOT append, and do NOT touch "Completed Work".
- Save files. Do NOT commit.
```

The overwrite-one-line rule is what enables no-op fix detection in the script. Keep it explicit.

## 4. build_memory_update_prompt(issue, title, round, outfile)

This is the only step allowed to record completed work — and it writes to the archive, per the governance memory rules.

```text
Update memory for completed issue #<issue>.

1. Add a ONE-LINE entry to `<ARCHIVE_FILE>` under the right phase heading.
2. Remove any "Next Up" status line for #<issue> in MEMORY.md.
3. Do NOT add issue detail to MEMORY.md — only update Next Up and blockers there.

Format: `- <title> (#<issue>): <brief what was built>. Last fix: <final fix>` (include "Last fix" only if <round> > 1)

Rules:
- 1-2 lines max. Don't document review cycles or reviewer names.
- Do NOT modify SOUL.md or AGENTS.md.
- MEMORY.md stays lean — see its Update Rules.
```

## 5. build_check_fix_prompt(issue, check_output, outfile)

```text
The implementation for issue #<issue> has failing checks. Fix them.

## Check output
<check_output>

## Instructions
- Fix the failing checks (<list the CHECK_CMDS>).
- Read SOUL.md for coding standards. Do NOT modify SOUL.md or AGENTS.md.
- Do NOT commit.
```

## Generation rules

- Always include "Do NOT modify SOUL.md or AGENTS.md" and "Do NOT commit" in every write-capable prompt — these enforce the skill boundaries inside the autonomous loop.
- Always include the single-status-line / overwrite / archive rules verbatim from the governance memory policy.
- Keep `{{GOVERNANCE_REVIEW_FOCUS}}` short and regenerate it on Audit/Sync so reviewers never enforce stale rules.
- Use heredocs to write prompts to temp files; never pass large prompts as CLI args.
