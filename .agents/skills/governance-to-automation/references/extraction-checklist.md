# Governance → Script Extraction Checklist

What to pull from each governance file to parameterize `auto-develop.sh`. Work through this in SKILL.md Step 1. For anything missing, emit `[NEEDS GOVERNANCE]` (route back to prd-to-governance) or `[USER DECISION REQUIRED]` (ask) — never guess.

## From SOUL.md

- [ ] **Stack / toolchain** → only `{{TOOLCHAIN_SETUP}}` if the commands need setup before running (PATH export, venv activation, runtime selection). The script makes no stack assumption; leave empty if none. The actual checks come from CLAUDE.md, not here.
- [ ] **Architecture invariants** → top items of `{{GOVERNANCE_REVIEW_FOCUS}}` (what reviewers must protect)
- [ ] **Coding standards** → review focus (strict types, export style, file organization, API/error conventions)
- [ ] **Security principles** → review focus (encryption, auth, validation/rate-limiting, secret handling)
- [ ] **Compliance** → review focus if it constrains code (privacy, accessibility)
- [ ] **Reference documents** → `{{REFERENCE_DOCS}}` the implementation/fix prompts tell agents to read

## From AGENTS.md

- [ ] **Roles** → implementation/reviewer role slots, any governance-suggested models or CLIs for those slots, and single-vs-dual review depth. Treat governance model names as defaults to confirm later, not as auto-binding output.
- [ ] **Git conventions** → `{{BASE_BRANCH}}`, branch pattern (`issue-<n>-<slug>`), commit format, force-push/hook policy
- [ ] **Prohibited actions** → the hard "do NOT" lines injected into every write-capable prompt + review focus
- [ ] **Review rules** → reviewer focus split (A vs B), what counts as a blocking finding, read-only enforcement
- [ ] **Delivery standard** → what "done" requires (drives whether the script stops at PR or merges)
- [ ] **Phase plan** → seed for the task source (issues or task-list)
- [ ] **Auto-Develop Policy** (if present) → binding rules already written for the pipeline; the script must match them exactly
- [ ] **Skill Policy** (if present) → `{{SKILL_MAP[]}}` — explicit matchers, one per line, `<type>:<pattern> = <skill>` with type `label` / `title` (the parser trims, so whitespace around `:` and `=` is optional). A `label` pattern is matched against the whole label, so multi-word labels (`good first issue`, `area: auth`) are fine; a `title` pattern is an extended regex against the task title/body. Absent = empty map (valid no-op); never invent matchers. Multiple distinct matches resolve to `(ambiguous)` at runtime, so flag any overlapping rules back as policy to tighten — do not add precedence here.

## From CLAUDE.md

- [ ] **Development Commands** → `{{CHECK_CMDS[]}}` in order; flag any `# planned` (not yet runnable → bootstrap first)
- [ ] **Single-test command** → used by check-fix and local validation
- [ ] **Tool preferences** → which CLIs/runners the script can use (`gh`, package manager, `claude`, `codex`, CI wrapper, etc.)
- [ ] **Roles** → confirm they match AGENTS.md; mismatch = `[GOVERNANCE DRIFT]`
- [ ] **Environment variables** → what the script must export or require; never hardcode secret values
- [ ] **Review boundary** → must stay in sync with AGENTS.md review roles
- [ ] **Operational guidance** → whether governance already implies detached execution expectations (`tmux`, runner host, CI, log paths)

## From MEMORY.md (the memory discipline — Critical)

- [ ] **Memory file path** → `{{MEMORY_FILE}}` (usually `MEMORY.md`)
- [ ] **Archive path** → `{{ARCHIVE_FILE}}` (usually `memory/completed-phases.md`); confirm it is not gitignored
- [ ] **Update Rules** → encode all of:
  - review diff excludes the memory file (`git diff <base> -- . ':!MEMORY.md'`)
  - implementation/fix steps write ONE overwritten "Next Up" line
  - only the post-review memory step writes completed work, to the archive
  - no-op fix detection (hash of code diff excluding memory + logs, via `git hash-object`)
- [ ] **Task source declaration** → GitHub Issues / task-list / Next Up (drives candidate selection)
- [ ] **Current blockers** → anything that should make the run refuse to start

## Cross-file consistency

- [ ] Review roles identical in AGENTS.md and CLAUDE.md (else `[GOVERNANCE DRIFT]`)
- [ ] Commands referenced in prompts/checks actually exist in CLAUDE.md
- [ ] Memory rules in the script match MEMORY.md *Update Rules* verbatim in intent
- [ ] Base branch in the script matches AGENTS.md git conventions
- [ ] `SKILL_MAP[]` matches the AGENTS.md *Skill Policy* or explicitly user-approved local entries (or is empty when there is none); no matcher was silently invented, and overlapping rules are flagged back rather than ordered by precedence. Every `title:` matcher is a **valid extended regex** (an invalid one resolves to no match at runtime and is only surfaced as a `skill-resolution.log` warning — catch it here instead)
- [ ] GitHub-issue mode includes a concrete issue-seeding plan from the AGENTS.md phase plan, not just a label convention

## Output of this step

A filled parameter set:

```
ROLE_SLOTS, GOVERNANCE_MODEL_DEFAULTS, CONFIRMED_MODEL_SELECTIONS(+effort/+runner),
BASE_BRANCH, TASK_SOURCE(+label/file), CHECK_CMDS[], TOOLCHAIN_SETUP, MEMORY_FILE,
ARCHIVE_FILE, REFERENCE_DOCS, GOVERNANCE_REVIEW_FOCUS (8-15 bullets),
PERMISSION_MODE/SANDBOX (user opt-in), MAX_ROUNDS, MERGE_POLICY,
ISSUE_SEED_PLAN, DETACHED_RUN_MODE,
SKILL_MAP[] (AGENTS.md Skill Policy + user-approved local entries; empty only if both absent)
```

Carry this into Step 4 (generate the script) and Step 5 (supporting artifacts).
