# auto-develop.sh Template

Structural blueprint for the generated pipeline. It is a proven issue-driven loop, generalized with `{{PLACEHOLDERS}}` the skill fills from governance. Keep the control flow; swap the project-specific values.

## Placeholder legend (governance → script)

| Placeholder | Source | Example |
|---|---|---|
| `{{IMPL_MODEL}}` / `{{REVIEW_A}}` / `{{REVIEW_B}}` | AGENTS.md *Roles*, CLAUDE.md | `sonnet` / `opus` / `gpt-5.4` |
| `{{BASE_BRANCH}}` | AGENTS.md *Git Conventions* | `main` |
| `{{TASK_LABEL}}` | task source decision | `agent:auto` |
| `{{CHECK_CMDS[]}}` | CLAUDE.md *Development Commands* | stack-agnostic — whatever the project lists, e.g. `pnpm lint` / `uv run pytest` / `cargo test` / `make check` |
| `{{TOOLCHAIN_SETUP}}` | CLAUDE.md / SOUL.md stack | optional; only what governance specifies (PATH export, `corepack enable`, `source .venv/bin/activate`, …) — empty if none |
| `{{MEMORY_FILE}}` / `{{ARCHIVE_FILE}}` | MEMORY.md *Update Rules* | `MEMORY.md` / `memory/completed-phases.md` |
| `{{REFERENCE_DOCS}}` | SOUL.md *Reference Documents* | `setup-guide.md` |
| `{{GOVERNANCE_REVIEW_FOCUS}}` | SOUL.md + AGENTS.md (see prompt-builders.md) | concise security/coding rule list |
| `{{PERMISSION_MODE}}` / `{{SANDBOX}}` | Step 3 user opt-in | `bypassPermissions` / `danger-full-access` |

For the **local task-list** source (no GitHub Issues), replace the `gh`-based candidate selection and PR/merge phases with: read the next unchecked task from the task-list file, branch, implement, check, review, commit, mark the task done. See `task-list-template.md`.

## Skeleton

```bash
#!/usr/bin/env bash
set -euo pipefail

# Issue-driven development loop. Only processes issues labeled `{{TASK_LABEL}}`.
# Skips issues whose `Depends on #N` references are still open.
# Pipeline per issue:
#   {{IMPL_MODEL}} implements -> checks -> {{REVIEW_A}} reviews -> {{REVIEW_B}} reviews
#   -> fix (if findings) -> re-check -> re-review -> repeat
# Exits cleanly when no eligible issue remains.

# --- Defaults (override via flags) ---
MAX_ISSUES=1
TARGET_ISSUE=""
MODEL="{{IMPL_MODEL}}"
REVIEW_A_MODEL="{{REVIEW_A}}"
REVIEW_A_EFFORT="high"
REVIEW_B_MODEL="{{REVIEW_B}}"     # omit entirely for single-review projects
REVIEW_B_EFFORT="high"
MAX_ROUNDS=100
DRY_RUN=false

LOGDIR="logs/issues"
BASE_BRANCH="{{BASE_BRANCH}}"
MEMORY_FILE="{{MEMORY_FILE}}"
ARCHIVE_FILE="{{ARCHIVE_FILE}}"
CLAUDE_PERMISSION_MODE="{{PERMISSION_MODE}}"   # requires explicit user opt-in

# Validation commands, taken verbatim from CLAUDE.md (stack-agnostic — no assumption
# about Node/Python/etc). Each runs in order; any non-zero exit fails the check phase.
CHECKS=(
  {{FOR each cmd in CHECK_CMDS}} "{{cmd}}"   # e.g. "pnpm lint", "uv run pytest", "cargo test", "go vet ./..."
  {{END}}
)
{{TOOLCHAIN_SETUP}}                            # optional; empty unless governance specifies setup

# --- Arg parsing: --max-issues --issue --model --review-a[-effort]
#     --review-b[-effort] --max-rounds --dry-run -h ---
# (standard while/case block; see the source example)

log()  { echo "[auto-develop $(date +%H:%M:%S)] $*"; }
die()  { log "FATAL: $*" >&2; exit 1; }

# Map short model names to CLI IDs.
resolve_claude_model() { case "$1" in
  sonnet) echo "claude-sonnet-4-6";;
  opus)   echo "claude-opus-4-6";;
  haiku)  echo "claude-haiku-4-5-20251001";;
  *)      echo "$1";; esac; }

# --- Worktree guards: never mix pre-existing changes into the run ---
git_status_outside_logs() { git status --porcelain --untracked-files=all -- . ":(exclude)$LOGDIR"; }
has_repo_changes_outside_logs() { [[ -n "$(git_status_outside_logs)" ]]; }
require_clean_worktree() {
  if has_repo_changes_outside_logs; then
    log "Working tree dirty outside $LOGDIR. Refusing to mix changes."; return 1; fi; }
stage_repo_changes() { git add -A -- . ":(exclude)$LOGDIR"; }

# --- Model runners: pipe prompt via stdin to avoid arg-length limits ---
run_claude_model() {  # <short_model> <effort> <prompt_file>
  local id; id="$(resolve_claude_model "$1")"
  if [[ -n "$2" ]]; then
    cat "$3" | claude -p - --model "$id" --effort "$2" \
      --permission-mode "$CLAUDE_PERMISSION_MODE" --output-format text 2>&1
  else
    cat "$3" | claude -p - --model "$id" \
      --permission-mode "$CLAUDE_PERMISSION_MODE" --output-format text 2>&1
  fi; }
run_model() { run_claude_model "$1" "" "$2"; }                 # impl/fix model
run_codex_model() {  # <model> <effort> <sandbox> <prompt_file>  (Reviewer B, optional)
  cat "$4" | codex exec --model "$1" --sandbox "$3" \
    ${2:+-c "model_reasoning_effort=\"$2\""} - 2>&1; }

slugify() { echo "$1" | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-40; }
ensure_logdir() { local d="$LOGDIR/$1"; mkdir -p "$d"; echo "$d"; }

# --- Issue eligibility + dependency blocking ---
issue_has_label() {  # <n>
  [[ "$(gh issue view "$1" --json labels \
    --jq '[.labels[].name]|map(select(.=="{{TASK_LABEL}}"))|length')" -gt 0 ]]; }
check_dependencies() {  # <n> -> non-zero if any "Depends on #N" is still open
  local body deps; body="$(gh issue view "$1" --json body --jq '.body')"
  deps="$(echo "$body" | grep -oiE 'depends on #[0-9]+' | grep -oE '[0-9]+' || true)"
  for d in $deps; do
    [[ "$(gh issue view "$d" --json state --jq '.state')" != "CLOSED" ]] && \
      { log "Blocked by #$d"; return 1; }; done; return 0; }

create_issue_branch() {  # <n> <title>
  local b="issue-$1-$(slugify "$2")"
  git show-ref --verify --quiet "refs/heads/$b" && git checkout "$b" || git checkout -b "$b"
  echo "$b"; }

# --- Checks: run each command in CHECKS[] in order; auto-fix once on failure.
#     Stack-agnostic: no package.json/runtime guard — the commands ARE the toolchain.
#     If CHECKS is empty (project declares none), the phase is a no-op pass. ---
run_checks() {  # <logfile>
  local failed=false
  [[ ${#CHECKS[@]} -eq 0 ]] && { echo "SKIP: no checks declared in CLAUDE.md" > "$1"; return 0; }
  {
    for cmd in "${CHECKS[@]}"; do
      echo "=== $cmd ==="
      eval "$cmd" 2>&1 || failed=true
    done
  } > "$1"
  [[ "$failed" == false ]]; }
ensure_checks_pass() {  # <issue> <logdir> <prefix>
  local cl="$2/$3.log"
  run_checks "$cl" && { log "Checks passed."; return 0; }
  log "Checks failed; auto-fixing..."
  build_check_fix_prompt "$1" "$(cat "$cl")" "$2/$3-fix-prompt.txt"
  run_model "$MODEL" "$2/$3-fix-prompt.txt" > "$2/$3-fix.log" 2>&1
  run_checks "$2/$3-rerun.log" && { log "Checks pass after fix."; return 0; }
  log "Checks still failing."; return 1; }

# --- Prompt builders: see prompt-builders.md (write to temp files) ---
# build_implementation_prompt / build_review_prompt / build_fix_prompt
# / build_memory_update_prompt / build_check_fix_prompt

# --- Review: diff EXCLUDES MEMORY.md and uses {{BASE_BRANCH}} (not base..HEAD)
#     so uncommitted fix-cycle changes are reviewed and status churn is hidden ---
run_review() {  # <label> <model> <effort> <issue> <title> <body> <logfile> <logdir>
  local diff; diff="$(git diff "$BASE_BRANCH" -- . ":!$MEMORY_FILE" 2>/dev/null || true)"
  [[ -z "$diff" ]] && { echo "LGTM (no changes)" > "$7"; return 0; }
  build_review_prompt "$1" "$4" "$5" "$6" "$diff" "$8/prompt-review.txt"
  if [[ "$1" == *Codex* || "$1" == *"Reviewer B"* ]]; then
    run_codex_model "$2" "$3" "{{SANDBOX}}" "$8/prompt-review.txt" > "$7" 2>&1
  else
    run_claude_model "$2" "$3" "$8/prompt-review.txt" > "$7" 2>&1
  fi
  grep -qi "^LGTM" "$7"; }   # LGTM = pass

# --- Per-issue pipeline ---
process_issue() {  # <issue>
  require_clean_worktree || return 1
  local issue="$1" title body logdir branch orig
  title="$(gh issue view "$issue" --json title --jq '.title')"
  body="$(gh issue view "$issue" --json body --jq '.body')"
  logdir="$(ensure_logdir "$issue")"; orig="$(git branch --show-current)"
  branch="$(create_issue_branch "$issue" "$title")"; log "Branch: $branch"

  # 1. Implement
  build_implementation_prompt "$issue" "$title" "$body" "$logdir/prompt-impl.txt"
  run_model "$MODEL" "$logdir/prompt-impl.txt" > "$logdir/01-impl.log" 2>&1 \
    || { git checkout "$orig"; return 1; }
  # 2. Checks
  ensure_checks_pass "$issue" "$logdir" "02-checks" || { git checkout "$orig"; return 1; }

  # 3. Review loop with no-op detection
  local round=1 passed=false
  while [[ "$round" -le "$MAX_ROUNDS" ]]; do
    local a="$logdir/03-rev-a-r$round.log" b="$logdir/03-rev-b-r$round.log" ap=true bp=true
    run_review "Reviewer A" "$REVIEW_A_MODEL" "$REVIEW_A_EFFORT" \
      "$issue" "$title" "$body" "$a" "$logdir" || ap=false
    # Omit the next block for single-review projects:
    run_review "Reviewer B (Codex)" "$REVIEW_B_MODEL" "$REVIEW_B_EFFORT" \
      "$issue" "$title" "$body" "$b" "$logdir" || bp=false
    [[ "$ap" == true && "$bp" == true ]] && { passed=true; break; }
    [[ "$round" -ge "$MAX_ROUNDS" ]] && { git checkout "$orig"; return 1; }

    local before after
    before="$(git diff "$BASE_BRANCH" -- . ":!$MEMORY_FILE" ":!$LOGDIR" | md5sum)"
    build_fix_prompt "$issue" "$title" "$body" "$a" "$b" "$round" "$logdir/prompt-fix-r$round.txt"
    run_model "$MODEL" "$logdir/prompt-fix-r$round.txt" > "$logdir/04-fix-r$round.log" 2>&1
    after="$(git diff "$BASE_BRANCH" -- . ":!$MEMORY_FILE" ":!$LOGDIR" | md5sum)"
    [[ "$before" == "$after" ]] && {
      log "No code change in fix cycle; remaining findings accepted."; passed=true; break; }
    ensure_checks_pass "$issue" "$logdir" "02-checks-r$round" || { git checkout "$orig"; return 1; }
    round=$((round + 1))
  done
  [[ "$passed" == true ]] || { git checkout "$orig"; return 1; }

  # 4. Memory step OWNS completed-work: archive entry + clear Next Up line
  build_memory_update_prompt "$issue" "$title" "$round" "$logdir/prompt-mem.txt"
  run_model "$MODEL" "$logdir/prompt-mem.txt" > "$logdir/04-mem.log" 2>&1

  # 5. Commit / PR  (merge ONLY if user opted in — otherwise stop here for human review)
  has_repo_changes_outside_logs || { log "No changes for #$issue."; git checkout "$orig"; return 1; }
  stage_repo_changes
  git commit -m "feat: implement #$issue - $title

Automated via auto-develop.sh. Model: $MODEL | Review: $REVIEW_A_MODEL${REVIEW_B_MODEL:+, $REVIEW_B_MODEL}
Review rounds: $round/$MAX_ROUNDS

Closes #$issue"
  git push -u origin "$branch"
  gh pr create --title "#$issue: $title" --body "Closes #$issue. Logs: \`$logdir/\`"
  # {{IF auto-merge opted in}} gh pr merge "$branch" --squash && git checkout "$BASE_BRANCH" && git pull
  log "=== Done #$issue ==="; }

# --- Candidate selection + main loop ---
if [[ -n "$TARGET_ISSUE" ]]; then
  issue_has_label "$TARGET_ISSUE" || die "#$TARGET_ISSUE lacks {{TASK_LABEL}}"
  CANDIDATES=("$TARGET_ISSUE")
else
  mapfile -t CANDIDATES < <(gh issue list --label "{{TASK_LABEL}}" --state open \
    --limit 200 --json number --jq '.[].number' | sort -n)
fi
[[ ${#CANDIDATES[@]} -eq 0 ]] && { log "No eligible issues."; exit 0; }

COMPLETED=0
for issue in "${CANDIDATES[@]}"; do
  [[ "$COMPLETED" -ge "$MAX_ISSUES" ]] && break
  check_dependencies "$issue" || { log "Skip #$issue (deps open)."; continue; }
  if [[ "$DRY_RUN" == true ]]; then log "[dry-run] would process #$issue"; COMPLETED=$((COMPLETED+1)); continue; fi
  process_issue "$issue" && COMPLETED=$((COMPLETED+1)) || log "#$issue produced no changes/failed."
done
log "Done. Completed $COMPLETED issue(s)."
```

## Generation rules

- **Keep the guards.** `require_clean_worktree`, dependency blocking, and the `git checkout "$orig"` rollback on failure are what make the loop safe to re-run.
- **Memory rules are mandatory** (see SKILL.md *Memory discipline*): the review diff must exclude `{{MEMORY_FILE}}`; the no-op `md5sum` comparison must exclude `{{MEMORY_FILE}}` and `$LOGDIR`; only `build_memory_update_prompt` writes the archive entry.
- **Diff against `{{BASE_BRANCH}}`, not `BASE..HEAD`** — uncommitted fix-cycle changes must be visible to reviewers or the loop never converges.
- **Pipe prompts via stdin** (`claude -p -`, `codex exec -`) to avoid "Argument list too long" on large diffs.
- **Stdlib only** — bash + `git` + `gh` (+ `codex` if Reviewer B). No extra deps unless governance lists them.
- **Privileged flags off by default** — only set `{{PERMISSION_MODE}}`/`{{SANDBOX}}` to bypass/danger levels when the user opted in (SKILL.md Step 3).
- **Stack-agnostic checks** — `run_checks` just iterates `CHECKS[]` from CLAUDE.md and `eval`s each command. Do not add runtime/manifest guards (`package.json`, `pyproject.toml`, …); the commands themselves are the toolchain. Empty `CHECKS[]` is a valid no-op pass.
- **No assumed model CLIs beyond what roles need** — `resolve_claude_model` and the Codex runner exist only because the example uses them; drop the Codex path for single-review projects and map model short-names to whatever the governance roles declare.
