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
  --no-refactor            Skip the post-review simplification pass
  --max-refactor-rounds <n> Max simplify->re-review rounds (default: 3)
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
#   -> fix (if findings) -> re-check -> re-review -> repeat (correctness pass)
#   -> refactor (simplify to senior quality) -> re-check -> re-review (A/B) -> repeat
#      until a refactor round changes nothing (refactor pass)
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
REFACTOR=true                 # second pass: simplify to senior quality, re-reviewed by A/B
MAX_REFACTOR_ROUNDS=3
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
    --refactor)        REFACTOR=true;         shift ;;
    --no-refactor)     REFACTOR=false;        shift ;;
    --max-refactor-rounds) MAX_REFACTOR_ROUNDS="$2"; shift 2 ;;
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
  [[ "$REFACTOR" == false ]] && args+=(--no-refactor)
  args+=(--max-refactor-rounds "$MAX_REFACTOR_ROUNDS")
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
# / build_refactor_prompt / build_memory_update_prompt / build_check_fix_prompt

# --- Review: diff EXCLUDES MEMORY.md and uses {{BASE_BRANCH}} (not base..HEAD)
#     so uncommitted fix-cycle changes are reviewed and status churn is hidden ---
run_review() {  # <label> <runner_fn> <issue> <title> <body> <logfile> <logdir>
  local diff; diff="$(git diff "$BASE_BRANCH" -- . ":!$MEMORY_FILE" 2>/dev/null || true)"
  [[ -z "$diff" ]] && { echo "LGTM (no changes)" > "$6"; return 0; }
  build_review_prompt "$1" "$3" "$4" "$5" "$diff" "$7/prompt-review.txt"
  "$2" "$7/prompt-review.txt" > "$6" 2>&1
  grep -qi "^LGTM" "$6"; }   # LGTM = pass

# --- Review-until-pass: A/B review + fix loop with no-op detection.
#     Reused for BOTH the correctness pass and the refactor re-validation.
#     Sets REVIEW_ROUNDS (final round) and REVIEW_OUTCOME (globals):
#       clean         = both reviewers passed
#       accepted-noop = reviewers had findings but a fix cycle changed no code
#                       (tolerated by the correctness pass to avoid infinite loops)
#       failed        = rounds exhausted or a check failed
#     Returns 0 for clean OR accepted-noop, 1 for failed. Callers that must NOT
#     tolerate unresolved findings (the refactor pass) check REVIEW_OUTCOME == clean,
#     not just the exit code. ---
review_until_pass() {  # <issue> <title> <body> <logdir> <stage>
  local issue="$1" title="$2" body="$3" logdir="$4" stage="$5" round=1
  REVIEW_ROUNDS=0; REVIEW_OUTCOME=failed
  while [[ "$round" -le "$MAX_ROUNDS" ]]; do
    REVIEW_ROUNDS="$round"
    local a="$logdir/$stage-rev-a-r$round.log" b="$logdir/$stage-rev-b-r$round.log" ap=true bp=true
    run_review "$REVIEW_A_LABEL" run_review_a_model "$issue" "$title" "$body" "$a" "$logdir" || ap=false
    # Omit the next line for single-review projects:
    run_review "$REVIEW_B_LABEL" run_review_b_model "$issue" "$title" "$body" "$b" "$logdir" || bp=false
    [[ "$ap" == true && "$bp" == true ]] && { REVIEW_OUTCOME=clean; return 0; }
    [[ "$round" -ge "$MAX_ROUNDS" ]] && { REVIEW_OUTCOME=failed; return 1; }
    local before after
    before="$(git diff "$BASE_BRANCH" -- . ":!$MEMORY_FILE" ":!$LOGDIR" | md5sum)"
    build_fix_prompt "$issue" "$title" "$body" "$a" "$b" "$round" "$logdir/$stage-fix-r$round.txt"
    run_impl_model "$logdir/$stage-fix-r$round.txt" > "$logdir/$stage-fix-r$round.log" 2>&1
    after="$(git diff "$BASE_BRANCH" -- . ":!$MEMORY_FILE" ":!$LOGDIR" | md5sum)"
    [[ "$before" == "$after" ]] && {
      log "No code change in fix cycle; remaining findings accepted."; REVIEW_OUTCOME=accepted-noop; return 0; }
    ensure_checks_pass "$issue" "$logdir" "$stage-checks-r$round" || { REVIEW_OUTCOME=failed; return 1; }
    round=$((round + 1))
  done
  REVIEW_OUTCOME=failed; return 1; }

# --- Refactor stage: SECOND pass. Runs on top of the COMMITTED correctness state
#     (HEAD is the per-issue checkpoint commit). Asks the impl model to simplify to
#     senior-engineer quality WITHOUT changing behavior, then re-validate via A/B.
#     A round is KEPT (amended into the checkpoint) only when its re-review is CLEAN.
#     If a round fails checks, fails review, OR its fix cycle no-ops while findings
#     remain (REVIEW_OUTCOME != clean), that round is REVERTED to the checkpoint and
#     refactoring stops — a degraded refactor is never accepted, and the already-
#     approved correctness work is never lost. Stops on no-op (converged) or
#     MAX_REFACTOR_ROUNDS. Accumulates DELIVERED_REVIEW_ROUNDS / REFACTOR_ROUNDS for
#     accurate commit + memory metadata. Same MEMORY.md/logs exclusions. ---
refactor_stage() {  # <issue> <title> <body> <logdir>
  [[ "$REFACTOR" == true ]] || { log "Refactor pass disabled (--no-refactor)."; return 0; }
  local issue="$1" title="$2" body="$3" logdir="$4" r=1 before after ok
  while [[ "$r" -le "$MAX_REFACTOR_ROUNDS" ]]; do
    before="$(git diff "$BASE_BRANCH" -- . ":!$MEMORY_FILE" ":!$LOGDIR" | md5sum)"
    build_refactor_prompt "$issue" "$title" "$body" "$r" "$logdir/05-refactor-r$r.txt"
    run_impl_model "$logdir/05-refactor-r$r.txt" > "$logdir/05-refactor-r$r.log" 2>&1
    after="$(git diff "$BASE_BRANCH" -- . ":!$MEMORY_FILE" ":!$LOGDIR" | md5sum)"
    [[ "$before" == "$after" ]] && { log "Refactor round $r: no change; code already clean."; return 0; }
    log "Refactor round $r changed code; re-checking and re-reviewing."
    ok=true
    ensure_checks_pass "$issue" "$logdir" "05-refactor-checks-r$r" || ok=false
    if [[ "$ok" == true ]]; then
      review_until_pass "$issue" "$title" "$body" "$logdir" "06-refactor-rev-r$r" || ok=false
      [[ "$REVIEW_OUTCOME" == clean ]] || ok=false   # no-op-accept is NOT good enough for a refactor
    fi
    if [[ "$ok" != true ]]; then
      log "Refactor round $r not cleanly approved; reverting this round to the checkpoint and stopping."
      git reset --hard HEAD >/dev/null 2>&1   # back to the checkpoint (correctness + prior clean refactors)
      git clean -fd >/dev/null 2>&1           # drop files the bad round added (logs/ is gitignored)
      return 0
    fi
    # Accepted: fold this cleanly-reviewed refactor into the checkpoint commit.
    DELIVERED_REVIEW_ROUNDS=$((DELIVERED_REVIEW_ROUNDS + REVIEW_ROUNDS))
    REFACTOR_ROUNDS="$r"
    stage_repo_changes
    git commit --amend --no-edit >/dev/null
    r=$((r + 1))
  done
  log "Reached MAX_REFACTOR_ROUNDS ($MAX_REFACTOR_ROUNDS); accepting current state."
  return 0; }

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

  # 3. Correctness review loop (A/B) with no-op fix detection
  review_until_pass "$issue" "$title" "$body" "$logdir" "03" || { git checkout "$orig"; return 1; }
  local review_rounds="$REVIEW_ROUNDS"
  DELIVERED_REVIEW_ROUNDS="$review_rounds"   # globals; refactor_stage accumulates accepted refactor re-reviews into these
  REFACTOR_ROUNDS=0

  # 3a. Checkpoint the correctness-approved state as the issue commit. This makes the
  #     refactor pass safe: a bad refactor reverts to THIS commit (correctness work is
  #     never lost), and only cleanly re-reviewed refactors are amended in. The guard
  #     here also prevents empty issue commits.
  has_repo_changes_outside_logs || { log "No changes for #$issue."; git checkout "$orig"; return 1; }
  stage_repo_changes
  git commit -m "feat: implement #$issue - $title (correctness)" >/dev/null

  # 3b. Refactor stage: simplify to senior quality on top of the checkpoint, re-validated
  #     by A/B. Reverts any round that is not cleanly approved; never fails the issue.
  #     Skipped entirely with --no-refactor.
  refactor_stage "$issue" "$title" "$body" "$logdir"

  # 4. Memory step OWNS completed-work: archive entry + clear Next Up line.
  #     Pass the correctness FIX rounds and the accepted REFACTOR rounds SEPARATELY —
  #     they mean different things. "Last fix" is gated on fix rounds (review_rounds),
  #     the simplification note on refactor rounds. Do not conflate them into one number.
  build_memory_update_prompt "$issue" "$title" "$review_rounds" "$REFACTOR_ROUNDS" "$logdir/prompt-mem.txt"
  run_impl_model "$logdir/prompt-mem.txt" > "$logdir/07-mem.log" 2>&1

  # 5. Fold memory + the final message into the ONE issue commit, then PR.
  #     (merge ONLY if user opted in — otherwise stop here for human review)
  stage_repo_changes
  local refactor_summary="off"
  [[ "$REFACTOR" == true ]] && refactor_summary="on (${REFACTOR_ROUNDS} round(s) applied)"
  git commit --amend -m "feat: implement #$issue - $title

Automated via auto-develop.sh. Model plan: $IMPL_LABEL | $REVIEW_A_LABEL${REVIEW_B_LABEL:+, $REVIEW_B_LABEL}
Correctness review rounds: $review_rounds/$MAX_ROUNDS (delivered A/B rounds incl. accepted refactor re-reviews: $DELIVERED_REVIEW_ROUNDS)
Refactor pass: $refactor_summary

Closes #$issue" >/dev/null
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
- **Share the review loop.** `review_until_pass` is the single A/B-review-plus-fix implementation; the correctness pass and the refactor re-validation both call it. Do not duplicate the review/no-op logic. It exposes `REVIEW_OUTCOME` (`clean` / `accepted-noop` / `failed`) so callers can tell a clean pass from a tolerated no-op.
- **Checkpoint the correctness state before refactoring.** The correctness-approved work is committed (the per-issue checkpoint) *before* the refactor pass runs. This is what makes the second pass safe and is mandatory: a refactor that is not cleanly approved reverts to the checkpoint (`git reset --hard HEAD` + `git clean -fd`), so correctness work is never lost and a degraded refactor is never kept. Cleanly-reviewed refactors are folded in with `git commit --amend`; the final commit message is set in one closing amend.
- **Refactor stage is gated, bounded, and never silently degrades.** It runs only after correctness passes, only when `REFACTOR=true`, and stops when a round changes nothing (`md5sum` no-op = converged) or `MAX_REFACTOR_ROUNDS` is reached. A round is **kept only when its re-review is `clean`** — failing checks, failing review, or a no-op fix cycle with findings still open (`REVIEW_OUTCOME != clean`) reverts that round. It is behavior-preserving simplification only — never a place to add features. `--no-refactor` must cleanly skip it.
- **Report the real history, with the right semantics.** The commit message reports the delivered A/B rounds (`DELIVERED_REVIEW_ROUNDS`: correctness plus accepted refactor re-reviews, not discarded refactor attempts) and `REFACTOR_ROUNDS`. The memory archive gets the correctness **fix** rounds (`review_rounds`) and `REFACTOR_ROUNDS` as *separate* arguments — never a conflated total — because "last fix" and "refactor rounds" are different facts; passing delivered review rounds into the "last fix" slot would imply fixes that never happened. `MEMORY.md` is part of the governance contract, so this accuracy is mandatory.
- **Pipe prompts via stdin** in the generated runner functions to avoid "Argument list too long" on large diffs.
- **Stdlib only** — bash + `git` + `gh` plus only the model CLIs the user explicitly selected. No extra deps unless governance lists them.
- **Privileged flags off by default** — only set `{{PERMISSION_MODE}}`/`{{SANDBOX}}` to bypass/danger levels when the user opted in (SKILL.md Step 3).
- **Detached runs should be first-class** — keep the `--tmux-session` / `--tmux-log` path working so long unattended batches can be launched safely without rewriting the script wrapper.
- **Stack-agnostic checks** — `run_checks` just iterates `CHECKS[]` from CLAUDE.md and `eval`s each command. Do not add runtime/manifest guards (`package.json`, `pyproject.toml`, …); the commands themselves are the toolchain. Empty `CHECKS[]` is a valid no-op pass.
- **No assumed model CLIs beyond what roles need** — Sonnet/Opus/Codex are examples, not defaults. Generate runner functions from the user-confirmed model/CLI plan and omit unused paths for single-review projects.
