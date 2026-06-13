# auto-develop.sh Template

Structural blueprint for the generated pipeline. It is a proven issue-driven loop, generalized with `{{PLACEHOLDERS}}` the skill fills from governance. Keep the control flow; swap the project-specific values.

## Placeholder legend (governance → script)

| Placeholder | Source | Example |
|---|---|---|
| `{{IMPL_MODEL}}` / `{{REVIEW_A}}` / `{{REVIEW_B}}` | Step 3 confirmed model selection, seeded from AGENTS.md / CLAUDE.md | `opus` / `sonnet` / `codex` |
| `{{IMPL_LABEL}}` / `{{REVIEW_A_LABEL}}` / `{{REVIEW_B_LABEL}}` | Step 3 confirmed review plan | `Implementation (Opus)` / `Reviewer A (Sonnet)` / `Reviewer B (Codex)` |
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

usage() {
  cat <<'EOF'
Usage: auto-develop.sh [OPTIONS]

Options:
  --max-issues <n>         Stop after completing n tasks/issues (default: 1)
  --issue <number>         Process only this specific issue
  --model <model>          Implementation/fix model
  --review-a <model>       Reviewer A model
  --review-a-effort <lvl>  Reviewer A reasoning effort (default: high)
  --review-b <model>       Reviewer B model (omit for single-review projects)
  --review-b-effort <lvl>  Reviewer B reasoning effort (default: high)
  --max-rounds <n>         Max review-fix rounds per issue (default: 100)
  --dry-run                Show planned work without executing model steps
  --tmux-session <name>    Launch the run in a detached tmux session, then exit
  --tmux-log <path>        Log file for detached tmux runs
  -h, --help               Show this help text

Examples:
  ./auto-develop.sh --max-issues 100
  ./auto-develop.sh --issue 42 --dry-run
  ./auto-develop.sh --max-issues 100 --tmux-session auto-develop
EOF
}

# Issue-driven development loop. Only processes issues labeled `{{TASK_LABEL}}`.
# Skips issues whose `Depends on #N` references are still open.
# Pipeline per issue:
#   {{IMPL_LABEL}} implements -> checks -> {{REVIEW_A_LABEL}} reviews -> {{REVIEW_B_LABEL}} reviews
#   -> fix (if findings) -> re-check -> re-review -> repeat
# Exits cleanly when no eligible issue remains.

# --- Defaults (override via flags) ---
MAX_ISSUES=1
TARGET_ISSUE=""
IMPL_LABEL="{{IMPL_LABEL}}"
MODEL="{{IMPL_MODEL}}"
IMPL_RUNNER="{{IMPL_RUNNER}}"
REVIEW_A_LABEL="{{REVIEW_A_LABEL}}"
REVIEW_A_MODEL="{{REVIEW_A}}"
REVIEW_A_RUNNER="{{REVIEW_A_RUNNER}}"
REVIEW_A_EFFORT="high"
REVIEW_B_LABEL="{{REVIEW_B_LABEL}}"   # omit entirely for single-review projects
REVIEW_B_MODEL="{{REVIEW_B}}"     # omit entirely for single-review projects
REVIEW_B_RUNNER="{{REVIEW_B_RUNNER}}" # omit entirely for single-review projects
REVIEW_B_EFFORT="high"
MAX_ROUNDS=100
DRY_RUN=false
TMUX_SESSION=""
TMUX_LOGFILE="logs/auto-develop.tmux.log"
NO_TMUX_REEXEC=false

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

# --- Arg parsing (keep this block; it backs the advertised CLI contract).
#     Omit the --review-b* cases for single-review projects. ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-issues)      MAX_ISSUES="$2";       shift 2 ;;
    --issue)           TARGET_ISSUE="$2";     shift 2 ;;
    --model)           MODEL="$2";            shift 2 ;;
    --review-a)        REVIEW_A_MODEL="$2";   shift 2 ;;
    --review-a-effort) REVIEW_A_EFFORT="$2";  shift 2 ;;
    --review-b)        REVIEW_B_MODEL="$2";   shift 2 ;;   # omit for single-review
    --review-b-effort) REVIEW_B_EFFORT="$2";  shift 2 ;;   # omit for single-review
    --max-rounds)      MAX_ROUNDS="$2";       shift 2 ;;
    --dry-run)         DRY_RUN=true;          shift ;;
    --tmux-session)    TMUX_SESSION="$2";     shift 2 ;;
    --tmux-log)        TMUX_LOGFILE="$2";     shift 2 ;;
    --no-tmux-reexec)  NO_TMUX_REEXEC=true;   shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

log()  { echo "[auto-develop $(date +%H:%M:%S)] $*"; }
die()  { log "FATAL: $*" >&2; exit 1; }

build_reexec_args() {
  local -a args
  args+=(--max-issues "$MAX_ISSUES")
  [[ -n "$TARGET_ISSUE" ]] && args+=(--issue "$TARGET_ISSUE")
  args+=(--model "$MODEL")
  args+=(--review-a "$REVIEW_A_MODEL" --review-a-effort "$REVIEW_A_EFFORT")
  [[ -n "$REVIEW_B_MODEL" ]] && args+=(--review-b "$REVIEW_B_MODEL" --review-b-effort "$REVIEW_B_EFFORT")
  args+=(--max-rounds "$MAX_ROUNDS")
  [[ "$DRY_RUN" == true ]] && args+=(--dry-run)
  args+=(--no-tmux-reexec)
  printf '%q ' "${args[@]}"
}

launch_in_tmux_if_requested() {
  [[ -z "$TMUX_SESSION" ]] && return 0
  [[ "$NO_TMUX_REEXEC" == true ]] && return 0
  [[ -n "${TMUX:-}" ]] && { log "Already inside tmux session '$TMUX_SESSION'; continuing in foreground."; return 0; }
  command -v tmux >/dev/null 2>&1 || die "tmux is required for --tmux-session"
  tmux has-session -t "$TMUX_SESSION" 2>/dev/null && die "tmux session '$TMUX_SESSION' already exists"
  mkdir -p "$(dirname "$TMUX_LOGFILE")"
  local reexec_args
  reexec_args="$(build_reexec_args)"
  tmux new-session -d -s "$TMUX_SESSION" "cd $(printf '%q' "$PWD") && $(printf '%q' "$0") $reexec_args | tee -a $(printf '%q' "$TMUX_LOGFILE")"
  log "Detached tmux session '$TMUX_SESSION' started."
  log "Reattach with: tmux attach -t $TMUX_SESSION"
  log "Live log: $TMUX_LOGFILE"
  exit 0
}

launch_in_tmux_if_requested

# --- Worktree guards: never mix pre-existing changes into the run ---
git_status_outside_logs() { git status --porcelain --untracked-files=all -- . ":(exclude)$LOGDIR"; }
has_repo_changes_outside_logs() { [[ -n "$(git_status_outside_logs)" ]]; }
require_clean_worktree() {
  if has_repo_changes_outside_logs; then
    log "Working tree dirty outside $LOGDIR. Refusing to mix changes."; return 1; fi; }
stage_repo_changes() { git add -A -- . ":(exclude)$LOGDIR"; }

# --- Model runners: generate these from the Step 3 confirmed model/CLI mapping.
# Example only: Sonnet/Opus may route through `claude -p`, Codex through `codex exec`.
# Do not assume those defaults; write the runner functions to match the user's selection.
run_impl_model() {      # <prompt_file>
  {{IMPL_RUNNER_CALL}}
}
run_review_a_model() {  # <prompt_file>
  {{REVIEW_A_RUNNER_CALL}}
}
# Omit entirely for single-review projects:
run_review_b_model() {  # <prompt_file>
  {{REVIEW_B_RUNNER_CALL}}
}

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
  run_impl_model "$2/$3-fix-prompt.txt" > "$2/$3-fix.log" 2>&1
  run_checks "$2/$3-rerun.log" && { log "Checks pass after fix."; return 0; }
  log "Checks still failing."; return 1; }

# --- Prompt builders: see prompt-builders.md (write to temp files) ---
# build_implementation_prompt / build_review_prompt / build_fix_prompt
# / build_memory_update_prompt / build_check_fix_prompt

# --- Review: diff EXCLUDES MEMORY.md and uses {{BASE_BRANCH}} (not base..HEAD)
#     so uncommitted fix-cycle changes are reviewed and status churn is hidden ---
run_review() {  # <label> <runner_fn> <issue> <title> <body> <logfile> <logdir>
  local diff; diff="$(git diff "$BASE_BRANCH" -- . ":!$MEMORY_FILE" 2>/dev/null || true)"
  [[ -z "$diff" ]] && { echo "LGTM (no changes)" > "$6"; return 0; }
  build_review_prompt "$1" "$3" "$4" "$5" "$diff" "$7/prompt-review.txt"
  "$2" "$7/prompt-review.txt" > "$6" 2>&1
  grep -qi "^LGTM" "$6"; }   # LGTM = pass

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
  run_impl_model "$logdir/prompt-impl.txt" > "$logdir/01-impl.log" 2>&1 \
    || { git checkout "$orig"; return 1; }
  # 2. Checks
  ensure_checks_pass "$issue" "$logdir" "02-checks" || { git checkout "$orig"; return 1; }

  # 3. Review loop with no-op detection
  local round=1 passed=false
  while [[ "$round" -le "$MAX_ROUNDS" ]]; do
    local a="$logdir/03-rev-a-r$round.log" b="$logdir/03-rev-b-r$round.log" ap=true bp=true
    run_review "$REVIEW_A_LABEL" run_review_a_model \
      "$issue" "$title" "$body" "$a" "$logdir" || ap=false
    # Omit the next block for single-review projects:
    run_review "$REVIEW_B_LABEL" run_review_b_model \
      "$issue" "$title" "$body" "$b" "$logdir" || bp=false
    [[ "$ap" == true && "$bp" == true ]] && { passed=true; break; }
    [[ "$round" -ge "$MAX_ROUNDS" ]] && { git checkout "$orig"; return 1; }

    local before after
    before="$(git diff "$BASE_BRANCH" -- . ":!$MEMORY_FILE" ":!$LOGDIR" | md5sum)"
    build_fix_prompt "$issue" "$title" "$body" "$a" "$b" "$round" "$logdir/prompt-fix-r$round.txt"
    run_impl_model "$logdir/prompt-fix-r$round.txt" > "$logdir/04-fix-r$round.log" 2>&1
    after="$(git diff "$BASE_BRANCH" -- . ":!$MEMORY_FILE" ":!$LOGDIR" | md5sum)"
    [[ "$before" == "$after" ]] && {
      log "No code change in fix cycle; remaining findings accepted."; passed=true; break; }
    ensure_checks_pass "$issue" "$logdir" "02-checks-r$round" || { git checkout "$orig"; return 1; }
    round=$((round + 1))
  done
  [[ "$passed" == true ]] || { git checkout "$orig"; return 1; }

  # 4. Memory step OWNS completed-work: archive entry + clear Next Up line
  build_memory_update_prompt "$issue" "$title" "$round" "$logdir/prompt-mem.txt"
  run_impl_model "$logdir/prompt-mem.txt" > "$logdir/04-mem.log" 2>&1

  # 5. Commit / PR  (merge ONLY if user opted in — otherwise stop here for human review)
  has_repo_changes_outside_logs || { log "No changes for #$issue."; git checkout "$orig"; return 1; }
  stage_repo_changes
  git commit -m "feat: implement #$issue - $title

Automated via auto-develop.sh. Model plan: $IMPL_LABEL | $REVIEW_A_LABEL${REVIEW_B_LABEL:+, $REVIEW_B_LABEL}
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
- **Pipe prompts via stdin** in the generated runner functions to avoid "Argument list too long" on large diffs.
- **Stdlib only** — bash + `git` + `gh` plus only the model CLIs the user explicitly selected. No extra deps unless governance lists them.
- **Privileged flags off by default** — only set `{{PERMISSION_MODE}}`/`{{SANDBOX}}` to bypass/danger levels when the user opted in (SKILL.md Step 3).
- **Detached runs should be first-class** — keep the `--tmux-session` / `--tmux-log` path working so long unattended batches can be launched safely without rewriting the script wrapper.
- **Stack-agnostic checks** — `run_checks` just iterates `CHECKS[]` from CLAUDE.md and `eval`s each command. Do not add runtime/manifest guards (`package.json`, `pyproject.toml`, …); the commands themselves are the toolchain. Empty `CHECKS[]` is a valid no-op pass.
- **No assumed model CLIs beyond what roles need** — Sonnet/Opus/Codex are examples, not defaults. Generate runner functions from the user-confirmed model/CLI plan and omit unused paths for single-review projects.
