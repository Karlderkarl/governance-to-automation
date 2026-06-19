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
| privileged execution | Step 3 user opt-in | **Not** a placeholder — generated scripts ship safe defaults (`default` / `workspace-write`) and reach privileged modes only via the runtime `--unattended` / `--auto-merge` flags behind `confirm_privileged_mode`. Never hardcode `bypassPermissions` / `danger-full-access` as a default. |
| `{{TEST_POLICY}}` / `{{TEST_ELIGIBILITY[]}}` | AGENTS.md *Auto-Develop Policy* | `required` plus `label:backend=include`, `title:^docs:=except` |
| `{{TARGETED_TEST_CMD}}` | CLAUDE.md *Development Commands* | `pytest {TARGET}` / `pnpm test -- --runTestsByPath {TARGET}` |
| `{{SKILL_MAP[]}}` | AGENTS.md *Skill Policy* + user-approved local entries (explicit matchers → skill) | `label:area:auth=security-hardening` — empty array only if both absent |

For the **local task-list** source (no GitHub Issues), replace the `gh`-based candidate selection and PR/merge phases with: read the next unchecked task from the task-list file, branch, implement, check, review, commit, mark the task done. See `task-list-template.md`. Keep `--dry-run` **read-only** in this variant too: select/print the next task but do **not** flip its status or write the task file — a dirtied task file would trip the next run's clean-worktree guard. Skill resolution still runs once per task, but a task-list task has no labels — so only `title:` matchers (against the task title/body) can resolve a skill in this variant; call `resolve_skill` with an empty label string.
The same deterministic rule applies to **test eligibility** in the task-list variant: with no labels available, only `title:` `TEST_ELIGIBILITY` matchers can make a task test-eligible; `label:` entries never match there, so a `label:`-only `except` set would fall through to the denylist base and must be flagged as governance drift during generation/audit rather than silently enabling tests for every task.

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
  --unattended             Opt in to privileged unattended execution
                           (bypassPermissions + danger-full-access). OFF by
                           default; prompts for confirmation (see --yes).
  --auto-merge             Squash-merge the PR after a clean review (OFF by default;
                           the run otherwise stops at the PR for human review).
  --yes                    Skip the privileged-mode confirmation prompt.
                           Required for non-interactive/detached (tmux) runs.
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
# Privileged execution is OFF by default. Do NOT hardcode bypassPermissions /
# danger-full-access as defaults — that is exactly what static scanners flag and
# what SKILL.md Step 3 forbids without explicit opt-in. --unattended raises both
# modes to their privileged values; --auto-merge enables the squash-merge. Nothing
# runs unattended unless the operator opts in AND confirms (confirm_privileged_mode).
CLAUDE_PERMISSION_MODE="default"               # --unattended -> bypassPermissions
CODEX_SANDBOX_MODE="workspace-write"           # --unattended -> danger-full-access (used by a sandboxed reviewer CLI, e.g. codex)
UNATTENDED=false
AUTO_MERGE=false
ASSUME_YES=false                               # --yes: skip the interactive confirmation (required for detached/tmux)
TEST_POLICY="{{TEST_POLICY}}"                  # off | preferred | required (opt-in; absent/empty => off)
TARGETED_TEST_CMD="{{TARGETED_TEST_CMD}}"      # must contain {TARGET}; may be empty when policy is off
TARGETED_TEST_FILE=""                          # set per issue inside process_issue
FROZEN_TARGETED_TEST_TARGET=""                 # set once a RED target is validated; reused for all later GREEN reruns
TEST_GATE_ACTIVE=false                         # per issue: true only when the HARD green gate is armed (required + confirmed RED)

# Skill resolution: explicit matchers -> skill, seeded from AGENTS.md "Skill Policy".
# Each entry is "<type>:<pattern>=<skill>" (whitespace around ':' and '=' is
# tolerated, so the spaced "<type>:<pattern> = <skill>" form the extraction
# checklist documents parses identically):
#   label:<issue-label>   match a task label  (most explicit; GitHub-issue source)
#   title:<ere>           match the task title/body (extended regex)
# Determinism rules (see resolve_skill): 0 distinct matches -> "(none)";
# exactly 1 distinct -> chosen; >1 distinct -> "(ambiguous)" and NOTHING is injected.
# No registry, no network, no semantic guessing. Empty array is a valid no-op default;
# an operator may also author entries locally (e.g. from a skill's own tags/triggers).
SKILL_MAP=(
  {{FOR each entry in SKILL_MAP}} "{{entry}}"   # e.g. "label:area:auth=security-hardening"
  {{END}}
)

# Test policy: explicit matchers -> include/except, seeded from AGENTS.md "Auto-Develop
# Policy". Entirely absent is the valid no-op default (off). Deterministic resolution
# (see resolve_test_policy) — `except` always wins over `include`, and the base default
# for an unmatched task depends on whether any include matchers are DECLARED:
#   task matches an except       -> exempt (off)                 [explicit deny beats allow]
#   else task matches an include -> eligible
#   else, include matchers declared -> not eligible (allowlist base)
#   else (only except declared)     -> eligible (denylist base: "test all except …")
# This makes "test everything except X" expressible with a single except matcher, and
# is fully deterministic (no "ambiguous" outcome, no heuristic). `required` without
# TARGETED_TEST_CMD is not silently enforced: the script degrades it to `preferred` and
# logs [GOVERNANCE DRIFT]. A set policy with an EMPTY eligibility array is inert -> off
# (and warned: governance is likely incomplete; should be caught at generation/audit).
TEST_ELIGIBILITY=(
  {{FOR each entry in TEST_ELIGIBILITY}} "{{entry}}"   # e.g. "label:backend=include"
  {{END}}
)

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
    --unattended)      UNATTENDED=true;       shift ;;
    --auto-merge)      AUTO_MERGE=true;       shift ;;
    --yes)             ASSUME_YES=true;       shift ;;
    --dry-run)         DRY_RUN=true;          shift ;;
    --tmux-session)    TMUX_SESSION="$2";     shift 2 ;;
    --tmux-log)        TMUX_LOGFILE="$2";     shift 2 ;;
    --no-tmux-reexec)  NO_TMUX_REEXEC=true;   shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# Raise the privileged values only when the operator explicitly opted in.
if [[ "$UNATTENDED" == true ]]; then
  CLAUDE_PERMISSION_MODE="bypassPermissions"
  CODEX_SANDBOX_MODE="danger-full-access"
fi

log()  { echo "[auto-develop $(date +%H:%M:%S)] $*"; }
die()  { log "FATAL: $*" >&2; exit 1; }

# Gate every privileged opt-in behind an explicit confirmation. A dry run touches
# nothing, so it is exempt. With --yes the prompt is skipped; without a TTY and
# without --yes we refuse rather than block a detached run forever.
confirm_privileged_mode() {
  [[ "$DRY_RUN" == true ]] && return 0
  local -a privileged=()
  [[ "$CLAUDE_PERMISSION_MODE" == "bypassPermissions" ]] && \
    privileged+=("Claude runs with --permission-mode=bypassPermissions (no per-action approval)")
  [[ "$CODEX_SANDBOX_MODE" == "danger-full-access" ]] && \
    privileged+=("sandboxed reviewer CLI runs with --sandbox=danger-full-access")
  [[ "$AUTO_MERGE" == true ]] && \
    privileged+=("PRs are squash-merged automatically after a clean review")
  [[ ${#privileged[@]} -eq 0 ]] && return 0   # fully safe defaults; nothing to confirm
  log "PRIVILEGED UNATTENDED MODE requested:"
  local item; for item in "${privileged[@]}"; do log "  - $item"; done
  if [[ "$ASSUME_YES" == true ]]; then log "Confirmed via --yes."; return 0; fi
  [[ -t 0 ]] || die "Privileged mode needs confirmation but no TTY is attached. Re-run with --yes."
  local reply=""; read -r -p "Proceed in privileged unattended mode? [y/N] " reply || true  # EOF -> empty -> clean abort
  [[ "$reply" =~ ^[Yy]$ ]] || die "Aborted by operator."
}
# Strip leading/trailing whitespace (used to parse SKILL_MAP tolerantly).
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

EFFECTIVE_TEST_POLICY="$(trim "$TEST_POLICY")"
# Absent/empty (unfilled placeholder) is the valid backward-compatible default.
[[ -z "$EFFECTIVE_TEST_POLICY" ]] && EFFECTIVE_TEST_POLICY="off"
case "$EFFECTIVE_TEST_POLICY" in
  off|preferred|required) ;;
  *) log "WARN: unknown TEST_POLICY '$EFFECTIVE_TEST_POLICY'; treating as off."; EFFECTIVE_TEST_POLICY="off" ;;
esac
if [[ "$EFFECTIVE_TEST_POLICY" == "required" && -z "$TARGETED_TEST_CMD" ]]; then
  EFFECTIVE_TEST_POLICY="preferred"
  log "[GOVERNANCE DRIFT] AGENTS.md sets TEST_POLICY=required but CLAUDE.md has no TARGETED_TEST_CMD; degrading enforcement to preferred."
fi
if [[ -n "$TARGETED_TEST_CMD" && "$TARGETED_TEST_CMD" != *"{TARGET}"* ]]; then
  die "TARGETED_TEST_CMD must contain a literal {TARGET} token"
fi

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
  [[ "$UNATTENDED" == true ]] && args+=(--unattended)
  [[ "$AUTO_MERGE" == true ]] && args+=(--auto-merge)
  [[ "$DRY_RUN" == true ]] && args+=(--dry-run)
  # The human already confirmed in the foreground; the detached run has no TTY.
  args+=(--yes)
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

# Confirm before detaching, so the human approves in the foreground and the
# detached tmux child inherits the approval via the propagated --yes.
confirm_privileged_mode
launch_in_tmux_if_requested

# --- Worktree guards: never mix pre-existing changes into the run ---
git_status_outside_logs() { git status --porcelain --untracked-files=all -- . ":(exclude)$LOGDIR"; }
has_repo_changes_outside_logs() { [[ -n "$(git_status_outside_logs)" ]]; }
require_clean_worktree() {
  if has_repo_changes_outside_logs; then
    log "Working tree dirty outside $LOGDIR. Refusing to mix changes."; return 1; fi; }
# Stage all work, then unstage the log dir. NOTE: do NOT use
# `git add -A -- . ":(exclude)$LOGDIR"` — when $LOGDIR is gitignored that pathspec
# makes `git add` exit 1 (matched-but-ignored path), which aborts the run under
# `set -e`. Plain `git add -A` skips ignored paths silently (exit 0); the reset then
# drops logs if they happen to be tracked.
stage_repo_changes() { git add -A; git reset -q -- "$LOGDIR" >/dev/null 2>&1 || true; }

# Abort helper for the per-issue failure paths: DISCARD any in-progress work, then return
# to BASE_BRANCH. A bare `git checkout "$orig"` is unsafe — half-written impl/fix changes
# either block the checkout or get carried onto the base branch, tripping the next run's
# clean-worktree guard. All callers run BEFORE the correctness checkpoint commit, so HEAD
# is still at the base tip and `reset --hard` only drops uncommitted work. `clean` excludes
# $LOGDIR explicitly so this issue's freshly written FAILURE logs survive for debugging even
# if the operator never gitignored logs/ (don't rely on the gitignore for that).
return_to_base() {
  git reset --hard HEAD >/dev/null 2>&1 || true
  git clean -fd -e "$LOGDIR" >/dev/null 2>&1 || true
  git checkout "$BASE_BRANCH" >/dev/null 2>&1 || log "WARN: could not return to $BASE_BRANCH"; }

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

# Branch the issue from BASE_BRANCH (never from the current HEAD) so successive issues in a
# --max-issues > 1 run never stack on an earlier, still-unmerged issue branch — otherwise
# issue N's review diff would include issue N-1's code.
create_issue_branch() {  # <n> <title>
  local b="issue-$1-$(slugify "$2")"
  if git show-ref --verify --quiet "refs/heads/$b"; then git checkout "$b"
  else git checkout -b "$b" "$BASE_BRANCH"; fi
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
resolve_test_policy() {  # <labels> <title> <body> <logdir>
  local labels="$1" title="$2" body="$3" logdir="$4"
  local text="$title"$'\n'"$body"
  local -a reasons=() warnings=()
  local entry lhs type pat effect matched type_ok regex_rc l include_count=0 except_count=0 decl_include=0 decl_except=0
  RESOLVED_TEST_POLICY="off"
  RESOLVED_TEST_REASON="test policy disabled"
  if [[ "$EFFECTIVE_TEST_POLICY" == "off" ]]; then
    {
      echo "searched: labels=[$(printf '%s' "$labels" | tr '\n' ',')] title=[$title]"
      echo "matches:   (none)"; echo "chosen:    off"; echo "reason:    $RESOLVED_TEST_REASON"
    } > "$logdir/test-policy.log"
    return 0
  fi
  # Policy is set but no eligibility matchers exist -> inert. Safe (off), but flag it:
  # this is governance incompleteness ([NEEDS GOVERNANCE]) that generation/audit should
  # have caught. Do not silently pretend testing is simply disabled.
  if [[ ${#TEST_ELIGIBILITY[@]} -eq 0 ]]; then
    RESOLVED_TEST_REASON="policy=$EFFECTIVE_TEST_POLICY but TEST_ELIGIBILITY is empty (inert) -> off"
    {
      echo "searched: labels=[$(printf '%s' "$labels" | tr '\n' ',')] title=[$title]"
      echo "matches:   (none)"; echo "chosen:    off"; echo "reason:    $RESOLVED_TEST_REASON"
    } > "$logdir/test-policy.log"
    log "WARN: TEST_POLICY=$EFFECTIVE_TEST_POLICY but no TEST_ELIGIBILITY matchers — policy is inert (treat as [NEEDS GOVERNANCE]). See $logdir/test-policy.log"
    return 0
  fi
  for entry in "${TEST_ELIGIBILITY[@]}"; do
    [[ "$entry" == *=* ]] || { warnings+=("malformed TEST_ELIGIBILITY entry '$entry' (no '=include'/'=except')"); continue; }
    effect="$(trim "${entry##*=}")"; lhs="${entry%=*}"
    type="$(trim "${lhs%%:*}")"; pat="$(trim "${lhs#*:}")"
    matched=false; type_ok=false
    case "$type" in
      label) type_ok=true; while IFS= read -r l; do [[ -n "$l" && "$l" == "$pat" ]] && matched=true; done <<< "$labels" ;;
      title) if [[ "$text" =~ $pat ]] 2>/dev/null; then
               type_ok=true; matched=true
             else
               regex_rc=$?
               if [[ "$regex_rc" -eq 2 ]]; then
                 warnings+=("invalid title: regex '$pat' (entry '$entry') — treated as no match")
               else
                 type_ok=true
               fi
             fi ;;
      *)     warnings+=("unknown TEST_ELIGIBILITY matcher type '$type' in '$entry'") ;;
    esac
    # Only a WELL-FORMED matcher (known type, valid title regex, known effect) is allowed to drive
    # the base default. A dead matcher (unknown type / invalid regex / unknown effect) must NOT
    # silently arm the denylist base ("test all except …") and switch testing on for every task.
    if [[ "$type_ok" == true ]]; then
      case "$effect" in
        include) decl_include=$((decl_include + 1)) ;;   # DECLARED, usable allow intent
        except)  decl_except=$((decl_except + 1)) ;;      # DECLARED, usable deny intent
        *)       warnings+=("unknown TEST_ELIGIBILITY effect '$effect' in '$entry'") ;;
      esac
    fi
    [[ "$matched" == true ]] || continue
    reasons+=("$type:$pat -> $effect")
    case "$effect" in
      include) include_count=$((include_count + 1)) ;;
      except)  except_count=$((except_count + 1)) ;;
    esac
  done
  # Deterministic precedence: except wins; then include; then base default by DECLARED, usable
  # intent. The denylist base ("eligible unless excepted") fires ONLY when a usable except matcher
  # was declared; with neither a usable include nor a usable except the set is inert -> fail safe
  # to off (governance incompleteness, [NEEDS GOVERNANCE]) rather than testing every task.
  if [[ "$except_count" -gt 0 ]]; then
    RESOLVED_TEST_POLICY="off"
    RESOLVED_TEST_REASON="exempt (except wins) via $(IFS='; '; echo "${reasons[*]}")"
  elif [[ "$include_count" -gt 0 ]]; then
    RESOLVED_TEST_POLICY="$EFFECTIVE_TEST_POLICY"
    RESOLVED_TEST_REASON="eligible via $(IFS='; '; echo "${reasons[*]}")"
  elif [[ "$decl_include" -gt 0 ]]; then
    RESOLVED_TEST_POLICY="off"
    RESOLVED_TEST_REASON="not test-eligible (allowlist base: include matchers declared, none matched)"
  elif [[ "$decl_except" -gt 0 ]]; then
    RESOLVED_TEST_POLICY="$EFFECTIVE_TEST_POLICY"
    RESOLVED_TEST_REASON="eligible (denylist base: only except matchers declared, none matched)"
  else
    RESOLVED_TEST_POLICY="off"
    RESOLVED_TEST_REASON="inert: no usable include/except matcher (all malformed/unknown/invalid) -> off"
    warnings+=("TEST_ELIGIBILITY has no usable matcher — policy inert (treat as [NEEDS GOVERNANCE])")
  fi
  {
    echo "searched: labels=[$(printf '%s' "$labels" | tr '\n' ',')] title=[$title]"
    echo "matches:"; printf '  - %s\n' "${reasons[@]:-(none)}"
    [[ ${#warnings[@]} -gt 0 ]] && { echo "warnings:"; printf '  - %s\n' "${warnings[@]}"; }
    echo "chosen:    $RESOLVED_TEST_POLICY"
    echo "reason:    $RESOLVED_TEST_REASON"
  } > "$logdir/test-policy.log"
  [[ ${#warnings[@]} -gt 0 ]] && log "WARN: ${#warnings[@]} TEST_ELIGIBILITY warning(s) — see $logdir/test-policy.log"
  log "Resolved test policy: $RESOLVED_TEST_POLICY ($RESOLVED_TEST_REASON)"
}
read_targeted_test_target() {  # <file>
  [[ -f "$1" ]] || return 1
  local target
  target="$(head -n 1 "$1" | tr -d '\r')"
  [[ -n "$target" ]] || return 1
  printf '%s' "$target"
}
# Deterministic, TARGETED red->green gate for a SINGLE test. This is a targeted TDD gate,
# NOT a full no-regression gate: it proves only that the one designated test went red->green.
# Broad regression protection is whatever CHECKS[] already provides (see KNOWN LIMITATION in
# the generation rules below). Mode:
#   expect_red   (test-first phase) -> pass(0) iff the target test exits NON-ZERO. This rejects a
#                tautological always-green test, but it does NOT prove the failure is an assertion
#                failure rather than a syntax/import/collection error: distinguishing those needs
#                framework-specific exit codes, which this stack-agnostic gate must not assume.
#                The "fails for the RIGHT reason" requirement is enforced by the test-authoring
#                PROMPT plus the mandatory expect_green pass on the SAME target (a test that was
#                red only from an import error must still be made to genuinely pass), NOT by exit
#                parsing. See KNOWN LIMITATION in the generation rules below.
#   expect_green (post-impl, default) -> ALWAYS reruns the target when one exists. If the hard
#                gate was armed (TEST_GATE_ACTIVE, set ONLY under `required`), pass(0) iff the
#                target test now PASSES. Under `preferred`, a still-red target is ADVISORY: it is
#                logged, fed into one check-fix attempt, and may still ship unresolved without
#                blocking the issue.
run_targeted_test_gate() {  # <logfile> [expect_red|expect_green]
  local logfile="$1" mode="${2:-expect_green}" target cmd rc=0 gate_mode="advisory"
  [[ "$mode" == "expect_green" && "$TEST_GATE_ACTIVE" == true ]] && gate_mode="hard"
  if [[ -z "$TARGETED_TEST_CMD" ]]; then
    echo "SKIP: no TARGETED_TEST_CMD configured" > "$logfile"; return 0
  fi
  if [[ "$mode" == "expect_green" && -n "$FROZEN_TARGETED_TEST_TARGET" ]]; then
    target="$FROZEN_TARGETED_TEST_TARGET"
  elif ! target="$(read_targeted_test_target "$TARGETED_TEST_FILE")"; then
    if [[ "$mode" == "expect_green" && "$gate_mode" != "hard" ]]; then
      echo "SKIP: no targeted test target written to $TARGETED_TEST_FILE (advisory mode)" > "$logfile"; return 0
    fi
    echo "FAIL: no targeted test target written to $TARGETED_TEST_FILE" > "$logfile"; return 1
  fi
  # SECURITY: the target is model-authored (lower trust than governance-authored CHECKS[])
  # and is substituted into an eval'd command. Allow only test-id/path characters — reject
  # anything that could inject shell. (']' first and '-' last keep the bracket expr literal.)
  if [[ ! "$target" =~ ^[][A-Za-z0-9_./:@=+#-]+$ ]]; then
    if [[ "$mode" == "expect_green" && "$gate_mode" != "hard" ]]; then
      echo "ADVISORY: targeted test target '$target' contains disallowed characters; preferred policy does not block" > "$logfile"; return 10
    fi
    echo "FAIL: targeted test target '$target' contains disallowed characters" > "$logfile"; return 1
  fi
  cmd="${TARGETED_TEST_CMD//\{TARGET\}/$target}"
  { echo "=== ($mode) $cmd ==="; eval "$cmd" 2>&1; } > "$logfile" || rc=$?
  if [[ "$mode" == "expect_red" ]]; then
    [[ "$rc" -ne 0 ]] && {
      FROZEN_TARGETED_TEST_TARGET="$target"
      echo "RED OK (exit $rc): non-zero before implementation (reason not exit-verified — see expect_red note)" >> "$logfile"
      echo "LOCKED TARGET: $FROZEN_TARGETED_TEST_TARGET" >> "$logfile"
      return 0
    }
    echo "NOT RED (exit 0): target passes without implementation — tautological or behavior already exists" >> "$logfile"; return 1
  fi
  [[ "$rc" -eq 0 ]] && { echo "GREEN OK" >> "$logfile"; return 0; }
  if [[ "$gate_mode" == "hard" ]]; then
    echo "NOT GREEN (exit $rc)" >> "$logfile"; return 1
  fi
  echo "ADVISORY: target still red after implementation (exit $rc); preferred policy does not block" >> "$logfile"; return 10; }
ensure_checks_pass() {  # <issue> <logdir> <prefix>
  local tl="$2/$3-targeted-test.log" cl="$2/$3.log" combo="$2/$3-combined.log" tg=0 rc=0
  # Run BOTH (no &&-short-circuit): under `set -e` a skipped run_checks would leave $cl
  # missing and the later `cat "$cl"` would abort the script before auto-fix. `|| x=$?`
  # also keeps a failing check from tripping `set -e` while we capture its status.
  run_targeted_test_gate "$tl" expect_green || tg=$?
  run_checks "$cl" || rc=$?
  [[ "$tg" -eq 0 && "$rc" -eq 0 ]] && { log "Checks passed."; return 0; }
  if [[ "$tg" -eq 10 && "$rc" -eq 0 ]]; then
    log "Targeted test remains advisory under preferred policy; checks are already green, so no auto-fix runs."
    return 0
  else
    log "Checks failed; auto-fixing..."
  fi
  { cat "$tl" 2>/dev/null; echo; cat "$cl" 2>/dev/null; } > "$combo"
  build_check_fix_prompt "$1" "$(cat "$combo")" "$2/$3-fix-prompt.txt"
  run_impl_model "$2/$3-fix-prompt.txt" > "$2/$3-fix.log" 2>&1
  tg=0; rc=0
  run_targeted_test_gate "$2/$3-rerun-targeted-test.log" expect_green || tg=$?
  run_checks "$2/$3-rerun.log" || rc=$?
  [[ "$tg" -eq 0 && "$rc" -eq 0 ]] && { log "Checks pass after fix."; return 0; }
  if [[ "$tg" -eq 10 && "$rc" -eq 0 ]]; then
    log "Checks pass, but the targeted test remains red under preferred policy (advisory only)."
    return 0
  fi
  log "Checks still failing."; return 1; }

# --- Prompt builders: see prompt-builders.md (write to temp files) ---
# build_implementation_prompt / build_review_prompt / build_fix_prompt
# / build_refactor_prompt / build_memory_update_prompt / build_check_fix_prompt
# / build_test_authoring_prompt (test-first RED phase; only when the gate is available)
# build_implementation_prompt, build_fix_prompt and build_refactor_prompt read the
# globals RESOLVED_SKILL / RESOLVED_SKILL_REASON set by resolve_skill (below) and
# inject a "Designated skill" block ONLY when RESOLVED_SKILL is a real skill. The
# prompts may also read RESOLVED_TEST_POLICY / RESOLVED_TEST_REASON plus
# TARGETED_TEST_FILE when governance opted into deterministic test enforcement.
# The memory prompt stays skill-neutral and test-policy-neutral.

# --- Deterministic skill resolution (see SKILL.md "Deterministic skill resolution").
#     Resolve ONCE per task from SKILL_MAP, log searched/candidates/chosen/reason,
#     and let only the implement/fix/refactor prompts inject the result. Outcomes:
#       (none)       no matcher matched (or SKILL_MAP empty) -> nothing injected
#       <skill>      exactly one DISTINCT skill matched      -> injected
#       (ambiguous)  >1 distinct skills matched              -> nothing injected, logged
#     No registry, no network, no semantic fallback: ambiguity is preferred over guessing.
#     Resolution runs before implementation, so it never depends on post-impl changes. ---
# <labels> is a NEWLINE-separated list (a single label may contain spaces, e.g.
# "good first issue" or "area: auth"). Matchers are trimmed, so spaced policy entries work.
# Only label: and title: matchers exist — both resolve deterministically without touching
# the filesystem. (A path: matcher was intentionally dropped: it was a no-op in GitHub-issue
# mode and filesystem-dependent in task-list mode. Reintroduce only with an explicit design.)
resolve_skill() {  # <labels> <title> <body> <logdir>
  local labels="$1" title="$2" body="$3" logdir="$4"
  local text="$title"$'\n'"$body"
  local -a reasons=() distinct=() warnings=()
  local entry lhs type pat skill matched regex_rc l d seen
  for entry in "${SKILL_MAP[@]}"; do
    [[ "$entry" == *=* ]] || continue
    skill="$(trim "${entry##*=}")"; lhs="${entry%=*}"
    type="$(trim "${lhs%%:*}")"; pat="$(trim "${lhs#*:}")"
    matched=false
    case "$type" in
      # Match each label as a WHOLE line; never word-split (would break labels with
      # spaces and could false-match a fragment of a multi-word label).
      label) while IFS= read -r l; do [[ -n "$l" && "$l" == "$pat" ]] && matched=true; done <<< "$labels" ;;
      # An invalid ERE makes [[ =~ ]] return 2 (not 1). Don't let a typo silently
      # skip a configured skill with only noisy stderr: suppress the diagnostic,
      # detect rc 2, and record an explicit warning into skill-resolution.log.
      title) if [[ "$text" =~ $pat ]] 2>/dev/null; then
               matched=true
             else
               regex_rc=$?
               if [[ "$regex_rc" -eq 2 ]]; then
                 warnings+=("invalid title: regex '$pat' (entry '$entry') — treated as no match")
               fi
             fi ;;
      *)     log "WARN: unknown SKILL_MAP matcher type '$type' in '$entry'" ;;
    esac
    [[ "$matched" == true ]] || continue
    reasons+=("$type:$pat -> $skill")
    seen=false; for d in "${distinct[@]}"; do [[ "$d" == "$skill" ]] && seen=true; done
    [[ "$seen" == false ]] && distinct+=("$skill")
  done
  if [[ ${#distinct[@]} -eq 0 ]]; then
    RESOLVED_SKILL="(none)"; RESOLVED_SKILL_REASON="no matcher matched"
  elif [[ ${#distinct[@]} -eq 1 ]]; then
    RESOLVED_SKILL="${distinct[0]}"; RESOLVED_SKILL_REASON="$(IFS='; '; echo "${reasons[*]}")"
  else
    RESOLVED_SKILL="(ambiguous)"; RESOLVED_SKILL_REASON="multiple distinct skills: $(IFS=', '; echo "${distinct[*]}")"
  fi
  {
    echo "searched: labels=[$(printf '%s' "$labels" | tr '\n' ',')] title=[$title]"
    echo "candidates:"; printf '  - %s\n' "${reasons[@]:-(none)}"
    [[ ${#warnings[@]} -gt 0 ]] && { echo "warnings:"; printf '  - %s\n' "${warnings[@]}"; }
    echo "chosen:    $RESOLVED_SKILL"
    echo "reason:    $RESOLVED_SKILL_REASON"
  } > "$logdir/skill-resolution.log"
  [[ ${#warnings[@]} -gt 0 ]] && log "WARN: ${#warnings[@]} invalid SKILL_MAP matcher(s) — see $logdir/skill-resolution.log"
  log "Resolved skill: $RESOLVED_SKILL ($RESOLVED_SKILL_REASON)"; }

# --- Code diff vs {{BASE_BRANCH}}, INCLUDING new files. CRITICAL: plain
#     `git diff <base>` omits UNTRACKED files, so a brand-new file from the
#     implementation would be invisible and reviewers would approve an empty diff.
#     Stage first (so new files register), then diff the index against base.
#     Excludes MEMORY.md; logs are never staged (pathspec exclude + usually gitignored). ---
stage_for_diff() { stage_repo_changes; }   # same staging; new files become visible to git diff
code_diff() { stage_for_diff; git diff --cached "$BASE_BRANCH" -- . ":!$MEMORY_FILE"; }
# Hash the code diff with `git hash-object` (git is already a hard dep), NOT `md5sum`:
# md5sum is absent by default on macOS/Windows, so under `set -euo pipefail` a generated
# script would die — less portable than the "bash + git + gh" contract claims. An empty
# diff hashes to the stable empty-blob id, so no-op detection still works.
code_hash() { stage_for_diff; git diff --cached "$BASE_BRANCH" -- . ":!$MEMORY_FILE" | git hash-object --stdin; }

# --- Review: uses code_diff (full uncommitted work vs {{BASE_BRANCH}} — new files
#     included, MEMORY.md excluded) so status churn is hidden but real changes are not ---
run_review() {  # <label> <runner_fn> <issue> <title> <body> <logfile> <logdir>
  local diff; diff="$(code_diff 2>/dev/null || true)"
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
    before="$(code_hash)"
    build_fix_prompt "$issue" "$title" "$body" "$a" "$b" "$round" "$logdir/$stage-fix-r$round.txt"
    run_impl_model "$logdir/$stage-fix-r$round.txt" > "$logdir/$stage-fix-r$round.log" 2>&1
    after="$(code_hash)"
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
    before="$(code_hash)"
    build_refactor_prompt "$issue" "$title" "$body" "$r" "$logdir/05-refactor-r$r.txt"
    run_impl_model "$logdir/05-refactor-r$r.txt" > "$logdir/05-refactor-r$r.log" 2>&1
    after="$(code_hash)"
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
      git clean -fd -e "$LOGDIR" >/dev/null 2>&1   # drop files the bad round added; keep this issue's logs
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
  local issue="$1" title body logdir branch
  title="$(gh issue view "$issue" --json title --jq '.title')"
  body="$(gh issue view "$issue" --json body --jq '.body')"
  logdir="$(ensure_logdir "$issue")"
  branch="$(create_issue_branch "$issue" "$title")"; log "Branch: $branch"
  TARGETED_TEST_FILE="$logdir/targeted-test.txt"
  rm -f "$TARGETED_TEST_FILE"
  FROZEN_TARGETED_TEST_TARGET=""
  TEST_GATE_ACTIVE=false

  # 0. Resolve the designated skill ONCE for this task (deterministic; logged).
  #    Globals RESOLVED_SKILL / RESOLVED_SKILL_REASON are then injected by the
  #    implement/fix/refactor prompt builders. Issue mode matches on labels; the local
  #    task-list variant (no labels) relies on title: matchers against the task title.
  local labels
  # Newline-join so multi-word labels ("good first issue") stay one token (see resolve_skill).
  labels="$(gh issue view "$issue" --json labels --jq '[.labels[].name]|join("\n")')"
  resolve_skill "$labels" "$title" "$body" "$logdir"
  resolve_test_policy "$labels" "$title" "$body" "$logdir"

  # 0a. Test-first (RED) sub-phase — only when a targeted test command exists and the task is
  #     test-eligible. Author ONLY the test(s), prove the target is RED before any implementation.
  #     The HARD red->green gate (TEST_GATE_ACTIVE -> enforced by ensure_checks_pass) is armed
  #     ONLY under `required`: a confirmed RED then makes the post-impl green a blocking gate.
#     Under `preferred` the test still ships and is rerun post-implementation, but green remains
#     ADVISORY — `preferred` must never hard-block or discard correctness work (that is what
#     `required` is for; see the asymmetric review channel). A confirmed RED target is FROZEN for
#     the rest of the task, so later prompts cannot retarget the gate to a different test. When
#     checks are already green, an advisory-only targeted-test miss is logged and returned as-is;
#     the pipeline must not mutate code just to chase an optional green. For `required`, an
#     unprovable RED fails the issue; `preferred` always continues with advisory guidance only.
  if [[ "$RESOLVED_TEST_POLICY" != "off" && -n "$TARGETED_TEST_CMD" ]]; then
    build_test_authoring_prompt "$issue" "$title" "$body" "$logdir/prompt-test.txt"
    run_impl_model "$logdir/prompt-test.txt" > "$logdir/00-test-author.log" 2>&1 \
      || { return_to_base; return 1; }
    if run_targeted_test_gate "$logdir/00-test-red.log" expect_red; then
      if [[ "$RESOLVED_TEST_POLICY" == "required" ]]; then
        TEST_GATE_ACTIVE=true
        log "RED confirmed before implementation; hard red->green gate is active (required)."
      else
        log "RED confirmed; preferred — the test ships and post-impl green is ADVISORY (no hard gate)."
      fi
    elif [[ "$RESOLVED_TEST_POLICY" == "required" ]]; then
      log "[TEST GATE] required: no RED baseline (missing/invalid target, or test already green); cannot prove red->green. Failing issue."
      return_to_base; return 1
    else
      log "[TEST GATE] preferred: no RED baseline; continuing with advisory test guidance only (no hard gate)."
    fi
  fi

  # 1. Implement
  build_implementation_prompt "$issue" "$title" "$body" "$logdir/prompt-impl.txt"
  run_impl_model "$logdir/prompt-impl.txt" > "$logdir/01-impl.log" 2>&1 \
    || { return_to_base; return 1; }
  # 2. Checks
  ensure_checks_pass "$issue" "$logdir" "02-checks" || { return_to_base; return 1; }

  # 3. Correctness review loop (A/B) with no-op fix detection
  review_until_pass "$issue" "$title" "$body" "$logdir" "03" || { return_to_base; return 1; }
  local review_rounds="$REVIEW_ROUNDS"
  DELIVERED_REVIEW_ROUNDS="$review_rounds"   # globals; refactor_stage accumulates accepted refactor re-reviews into these
  REFACTOR_ROUNDS=0

  # 3a. Checkpoint the correctness-approved state as the issue commit. This makes the
  #     refactor pass safe: a bad refactor reverts to THIS commit (correctness work is
  #     never lost), and only cleanly re-reviewed refactors are amended in. Gate on a
  #     non-empty CODE diff (excludes MEMORY.md/logs), NOT has_repo_changes_outside_logs:
  #     run_review auto-LGTMs an empty code diff, so a model that only rewrote the
  #     MEMORY.md "Next Up" line would otherwise pass review and produce a memory-only
  #     "implemented" commit + PR. No code change => nothing was built => skip the issue.
  [[ -n "$(code_diff)" ]] || { log "No code changes for #$issue (only MEMORY.md/logs)."; return_to_base; return 1; }
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
  # Return to BASE_BRANCH so the NEXT issue branches from a clean base rather than stacking
  # on this still-unmerged branch. Safe: everything is committed at this point.
  git checkout "$BASE_BRANCH" >/dev/null 2>&1 || log "WARN: could not return to $BASE_BRANCH"
  # Auto-merge ONLY when the operator opted in (and confirmed); otherwise stop at the
  # PR for human review. Already on $BASE_BRANCH, so a successful merge + pull is safe.
  if [[ "$AUTO_MERGE" == true ]]; then
    # A failed merge/pull must NOT count as a completed issue (matches the sample fixture):
    # report the failure so the loop's `|| log "...failed"` fires and the issue is not counted.
    if ! { gh pr merge "$branch" --squash && git pull; }; then
      log "ERROR: auto-merge/pull failed for #$issue; PR left open for manual handling."
      return 1
    fi
  else
    log "PR opened for #$issue; auto-merge OFF (enable with --auto-merge). Awaiting human review."
  fi
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

- **Keep the guards.** `require_clean_worktree`, dependency blocking, and the `return_to_base` rollback on failure are what make the loop safe to re-run. The rollback must **discard** in-progress work (`git reset --hard` + `git clean -fd -e "$LOGDIR"`, which keeps this issue's freshly written failure logs) before switching back, never a bare `git checkout "$orig"` — a half-written impl/fix would otherwise block the checkout or follow onto the base branch and trip the next run's clean-worktree guard.
- **Branch from the base branch, and return to it after every issue.** `create_issue_branch` must start each new issue from `{{BASE_BRANCH}}` (`git checkout -b "$b" "$BASE_BRANCH"`), and the success path must `git checkout "$BASE_BRANCH"` after opening the PR. Otherwise, in a `--max-issues > 1` run, issue N branches off issue N-1's still-unmerged tip and its review diff includes the previous issue's code.
- **Gate the correctness commit on a non-empty CODE diff**, not on `has_repo_changes_outside_logs`. `run_review` auto-approves an empty `code_diff`, so a model that only rewrote the `{{MEMORY_FILE}}` "Next Up" line would otherwise pass review and produce a memory-only "implemented" commit + PR. Use `[[ -n "$(code_diff)" ]]` (excludes `{{MEMORY_FILE}}`/logs) as the checkpoint guard — no code change means nothing was built.
- **Review/no-op diffs must include new files.** Build every review diff and no-op hash from a *staged* diff (`stage_for_diff` + `git diff --cached <base>`), never plain `git diff <base>` — the latter omits untracked files, so a brand-new implementation file would be reviewed as an empty diff and silently approved. Use the `code_diff` / `code_hash` helpers everywhere a code diff is needed.
- **Stage with `git add -A` + unstage `$LOGDIR`, not `git add -- . :(exclude)$LOGDIR`.** When the log dir is gitignored (the recommended setup), the `:(exclude)` pathspec makes `git add` exit 1 on the matched-but-ignored path, which kills the run under `set -e`. Plain `git add -A` skips ignored paths silently; follow with `git reset -q -- "$LOGDIR"` to keep logs out of commits when they are *not* ignored.
- **`--dry-run` is side-effect-free.** It may select and print candidate work but must never mutate tracked files — no task-status flip, no commit, no PR. In the local task-list variant, guard `task_mark_status` (and any task-file write) behind `[[ "$DRY_RUN" != true ]]`; a dirtied task file would trip the next run's clean-worktree guard.
- **Memory rules are mandatory** (see SKILL.md *Memory discipline*): the review diff must exclude `{{MEMORY_FILE}}`; the no-op `code_hash` comparison must exclude `{{MEMORY_FILE}}` and `$LOGDIR`; only `build_memory_update_prompt` writes the archive entry.
- **Diff against `{{BASE_BRANCH}}`, not `BASE..HEAD`** — uncommitted fix-cycle changes must be visible to reviewers or the loop never converges.
- **Share the review loop.** `review_until_pass` is the single A/B-review-plus-fix implementation; the correctness pass and the refactor re-validation both call it. Do not duplicate the review/no-op logic. It exposes `REVIEW_OUTCOME` (`clean` / `accepted-noop` / `failed`) so callers can tell a clean pass from a tolerated no-op.
- **Checkpoint the correctness state before refactoring.** The correctness-approved work is committed (the per-issue checkpoint) *before* the refactor pass runs. This is what makes the second pass safe and is mandatory: a refactor that is not cleanly approved reverts to the checkpoint (`git reset --hard HEAD` + `git clean -fd -e "$LOGDIR"`), so correctness work is never lost and a degraded refactor is never kept. Cleanly-reviewed refactors are folded in with `git commit --amend`; the final commit message is set in one closing amend.
- **Refactor stage is gated, bounded, and never silently degrades.** It runs only after correctness passes, only when `REFACTOR=true`, and stops when a round changes nothing (`code_hash` no-op = converged) or `MAX_REFACTOR_ROUNDS` is reached. A round is **kept only when its re-review is `clean`** — failing checks, failing review, or a no-op fix cycle with findings still open (`REVIEW_OUTCOME != clean`) reverts that round. It is behavior-preserving simplification only — never a place to add features. `--no-refactor` must cleanly skip it.
- **Report the real history, with the right semantics.** The commit message reports the delivered A/B rounds (`DELIVERED_REVIEW_ROUNDS`: correctness plus accepted refactor re-reviews, not discarded refactor attempts) and `REFACTOR_ROUNDS`. The memory archive gets the correctness **fix** rounds (`review_rounds`) and `REFACTOR_ROUNDS` as *separate* arguments — never a conflated total — because "last fix" and "refactor rounds" are different facts; passing delivered review rounds into the "last fix" slot would imply fixes that never happened. `MEMORY.md` is part of the governance contract, so this accuracy is mandatory.
- **Pipe prompts via stdin** in the generated runner functions to avoid "Argument list too long" on large diffs.
- **Stdlib only** — bash + `git` + `gh` plus only the model CLIs the user explicitly selected. No extra deps unless governance lists them. In particular, hash code diffs with `git hash-object --stdin` (git is already required), **not** `md5sum`/`md5` — those are absent by default on macOS/Windows and would make the script die under `set -euo pipefail`.
- **Privileged flags off by default, behind a runtime confirmation.** Generated scripts must ship safe defaults (`CLAUDE_PERMISSION_MODE="default"`, `CODEX_SANDBOX_MODE="workspace-write"`, `AUTO_MERGE=false`) and reach privileged modes only via the `--unattended` / `--auto-merge` flags. Do **not** hardcode `bypassPermissions` / `danger-full-access` / an unconditional `gh pr merge` as defaults — that is what static scanners (Socket/Snyk) flag and what SKILL.md Step 3 forbids without explicit opt-in. Keep `confirm_privileged_mode` and its call before `launch_in_tmux_if_requested`: it lists the requested privileges and prompts `[y/N]`, is skipped by `--dry-run` and `--yes`, and **refuses** (rather than blocks) when no TTY is attached and `--yes` was not given. The tmux re-exec must propagate `--unattended`/`--auto-merge` and append `--yes`, so the human confirms once in the foreground and the detached child does not re-prompt. A sandboxed reviewer CLI (e.g. `codex exec`) takes its `--sandbox` from `$CODEX_SANDBOX_MODE`, never a literal.
- **Detached runs should be first-class** — keep the `--tmux-session` / `--tmux-log` path working so long unattended batches can be launched safely without rewriting the script wrapper.
- **Stack-agnostic checks** — `run_checks` just iterates `CHECKS[]` from CLAUDE.md and `eval`s each command. Do not add runtime/manifest guards (`package.json`, `pyproject.toml`, …); the commands themselves are the toolchain. Empty `CHECKS[]` is a valid no-op pass.
- **No assumed model CLIs beyond what roles need** — Sonnet/Opus/Codex are examples, not defaults. Generate runner functions from the user-confirmed model/CLI plan and omit unused paths for single-review projects.
- **Skill resolution is deterministic and logged.** `resolve_skill` runs exactly once per task (before implementation), seeded from `SKILL_MAP` (AGENTS.md *Skill Policy*). An empty `SKILL_MAP` is a valid no-op (`(none)`); exactly one distinct match is chosen; **more than one distinct match is `(ambiguous)` — inject nothing and log it, never pick one**. There is no registry, no network, and no semantic fallback. Every decision is written to `$logdir/skill-resolution.log` (`searched` / `candidates` / `chosen` / `reason`). The result is injected **only** into the implement/fix/refactor prompts — reviewers, check-fix, and the memory step stay skill-neutral.
- **Test policy is equally deterministic and opt-in.** `TEST_POLICY=off` (or absent/empty, normalized to `off`) is the valid default. `TEST_ELIGIBILITY` uses only explicit `label:` / `title:` include-or-except matchers, resolved once per task and logged to `$logdir/test-policy.log`. Resolution is fully deterministic with no "ambiguous" outcome: **`except` wins over `include`**; otherwise an `include` match is eligible; otherwise the base default follows the **DECLARED, well-formed** matchers — allowlist (not eligible) when usable include matchers are declared, or denylist (eligible) when only usable except matchers are declared. Only well-formed matchers (known type, valid `title:` regex, known effect) drive the base default: a **dead** matcher (unknown type, invalid regex, malformed entry) is logged as a warning and must **not** arm the denylist base. A set whose eligibility array is empty **or contains no usable matcher** is inert → `off` **and warned** (governance incompleteness, `[NEEDS GOVERNANCE]`) — it never falls through to "test every task". There is no heuristic "behavioral change" detector.
- **The gate is a red→green transition proof, not a green-only smoke test — but the RED *reason* is not exit-verified.** When the gate is available (policy enforced for the task **and** `TARGETED_TEST_CMD` set), a test-first sub-phase authors the test(s) and runs the target in `expect_red` mode **before** implementation — it must exit NON-ZERO (a tautological always-green test is rejected). **Honest scope:** a non-zero exit does *not* prove the failure is an assertion failure rather than a syntax/import/collection error — telling those apart needs framework-specific exit codes, which this stack-agnostic gate deliberately does not assume. "Fails for the right reason" is enforced by the **test-authoring prompt** (which demands an assertion-level failure, not a collection error) plus the post-impl rerun of the **same** target — not by parsing exit codes. Do not describe this as exit-verified. Once a RED target is confirmed, the script FREEZES that exact target for the rest of the task, so later prompts cannot retarget the proof to an easier test. The hard gate is armed (`TEST_GATE_ACTIVE`) **only under `required`** — there a confirmed RED makes the post-impl `expect_green` in `ensure_checks_pass` a blocking gate, and the pair proves the red→green *transition*. Under `preferred` the targeted test is still rerun after implementation, but an unresolved failure stays advisory rather than blocking the issue or triggering extra code mutation when `CHECKS[]` are already green. For `required`, an unprovable RED fails the issue; `preferred` degrades to advisory (no hard gate). The model writes exactly one affected test id/path to `TARGETED_TEST_FILE`; the script **sanitizes** it (test-id/path characters only) before substituting into `{TARGET}`, because that value is model-authored and reaches an `eval`. If AGENTS.md says `required` but CLAUDE.md has no `TARGETED_TEST_CMD`, the script logs `[GOVERNANCE DRIFT]` and degrades to `preferred` instead of pretending a hard gate exists.
- **KNOWN LIMITATION — targeted gate, not a full no-regression gate (v1).** The red→green proof covers **only the one designated test**. It is deliberately *not* a general "no other test regressed" guarantee. Broad regression protection is exactly whatever `CHECKS[]` already runs and no more — so a project whose `CHECKS[]` is a full suite that is **already red before the task** will block the pipeline (every `CHECKS[]` command must pass), and a project whose `CHECKS[]` omits the suite gets no regression coverage beyond the single targeted test. Do not describe or generate this as a full no-regression gate. **Future extension (separate work):** capture a `CHECKS[]` baseline *only when the suite is green before the task*, compare after, and when the pre-task suite is already red, disable the no-regression comparison and log it clearly rather than blocking — see the matching note in SKILL.md.
