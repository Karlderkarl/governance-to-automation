#!/usr/bin/env bash
#
# ============================================================================
#  EXAMPLE / SAMPLE OUTPUT — NOT THIS REPOSITORY'S AUTOMATION. DO NOT RUN HERE.
# ============================================================================
#  This is a *generated* auto-develop.sh, produced by the
#  `governance-to-automation` skill for a specific Node/pnpm + Payload CMS
#  project. It is kept only as a concrete fixture showing what fully-resolved
#  skill output looks like (real runner functions, model resolution, etc.).
#
#  NOTE: this is a pre-refactor-pass snapshot. The skill has since gained a
#  second, refactor pass (review_until_pass + refactor_stage, --no-refactor /
#  --max-refactor-rounds). This fixture is intentionally NOT re-synced; for the
#  current pipeline shape see
#  .agents/skills/governance-to-automation/references/auto-develop-template.md.
#
#  It is project-specific (hardcoded `master` base branch and pnpm PATH).
#
#  Privileged modes match the skill's policy: OFF by default, reachable only
#  via explicit opt-in flags, and gated behind an interactive confirmation
#  (`confirm_privileged_mode`) so an unattended run can never start silently:
#    - --unattended  → Claude `bypassPermissions` + Codex `danger-full-access`
#    - --auto-merge  → `gh pr merge --squash` (otherwise the run stops at the PR)
#    - --yes         → skip the confirmation prompt (required for detached/tmux,
#                      which has no TTY); the tmux re-exec adds it automatically
#                      after the human confirms once in the foreground.
#  See ../CLAUDE.md and the template at
#  .agents/skills/governance-to-automation/references/auto-develop-template.md.
#
#  Treat this file as read-only reference. Do not execute it in this repo.
# ============================================================================

set -euo pipefail

# Issue-driven development loop for Claude Code.
# Only processes issues labeled `agent:auto`.
# Skips issues whose `Depends on #N` references are still open.
#
# Pipeline per issue:
#   Sonnet implements → checks → Opus reviews → Codex reviews
#   → Sonnet fixes (if findings) → re-check → re-review → repeat
#
# Exits cleanly when no eligible issue remains.

usage() {
  cat <<'EOF'
Usage: auto-develop.sh [OPTIONS]

Options:
  --max-issues <n>       Stop after completing n issues (default: 1)
  --issue <number>       Process only this specific open issue
  --model <model>        Claude model for implementation (default: sonnet)
  --review-a <model>     Reviewer A model (default: opus)
  --review-a-effort <level>
                         Reviewer A reasoning effort (default: high)
  --review-b <model>     Reviewer B model via Codex CLI (default: gpt-5.4)
  --review-b-effort <level>
                          Reviewer B reasoning effort (default: high)
  --max-rounds <n>       Max review-fix rounds per issue (default: 100)
  --unattended           Opt in to privileged unattended execution:
                         Claude bypassPermissions + Codex danger-full-access.
                         OFF by default; prompts for confirmation (see --yes).
  --auto-merge           Squash-merge the PR after a clean review.
                         OFF by default; the run otherwise stops at the PR.
  --yes                  Skip the privileged-mode confirmation prompt.
                         Required for non-interactive/detached (tmux) runs.
  --dry-run              Show planned steps without executing
  --tmux-session <name>  Launch the run in a detached tmux session, then exit
  --tmux-log <path>      Log file for detached tmux runs
  -h, --help             Show this help text

Model short names:
  sonnet   → claude-sonnet-4-6    (claude -p)
  opus     → claude-opus-4-6      (claude -p)
  haiku    → claude-haiku-4-5-20251001 (claude -p)
  codex    -> gpt-5.4              (codex exec)
  Full model IDs are also accepted for Claude models.

Examples:
  ./auto-develop.sh --max-issues 100
  ./auto-develop.sh --issue 42 --dry-run
  ./auto-develop.sh --max-issues 100 --tmux-session auto-develop
EOF
}

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

MAX_ISSUES=1
TARGET_ISSUE=""
MODEL="sonnet"
REVIEW_A_MODEL="opus"
REVIEW_A_EFFORT="high"
REVIEW_B_MODEL="gpt-5.4"
REVIEW_B_EFFORT="high"
MAX_ROUNDS=100
DRY_RUN=false
TMUX_SESSION=""
TMUX_LOGFILE="logs/auto-develop.tmux.log"
NO_TMUX_REEXEC=false

LOGDIR="logs/issues"

# Privileged execution is OFF by default. --unattended raises both of these to
# their privileged values; --auto-merge enables the squash-merge. Nothing here
# runs unattended unless the operator opts in AND confirms (see
# confirm_privileged_mode below).
CLAUDE_PERMISSION_MODE="default"        # --unattended → bypassPermissions
CODEX_SANDBOX_MODE="workspace-write"    # --unattended → danger-full-access
UNATTENDED=false
AUTO_MERGE=false
ASSUME_YES=false                        # --yes: skip the interactive confirmation

# Ensure pnpm is available regardless of how the script is invoked
export PATH="/home/dev/.local/share/pnpm:$PATH"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-issues)  MAX_ISSUES="$2";      shift 2 ;;
    --issue)       TARGET_ISSUE="$2";    shift 2 ;;
    --model)       MODEL="$2";           shift 2 ;;
    --review-a)    REVIEW_A_MODEL="$2";  shift 2 ;;
    --review-a-effort) REVIEW_A_EFFORT="$2"; shift 2 ;;
    --review-b)    REVIEW_B_MODEL="$2";  shift 2 ;;
    --review-b-effort) REVIEW_B_EFFORT="$2"; shift 2 ;;
    --max-rounds)  MAX_ROUNDS="$2";      shift 2 ;;
    --unattended)  UNATTENDED=true;      shift ;;
    --auto-merge)  AUTO_MERGE=true;      shift ;;
    --yes)         ASSUME_YES=true;      shift ;;
    --dry-run)     DRY_RUN=true;         shift ;;
    --tmux-session) TMUX_SESSION="$2";   shift 2 ;;
    --tmux-log)    TMUX_LOGFILE="$2";    shift 2 ;;
    --no-tmux-reexec) NO_TMUX_REEXEC=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Raise the privileged values only when the operator explicitly opted in.
if [[ "$UNATTENDED" == true ]]; then
  CLAUDE_PERMISSION_MODE="bypassPermissions"
  CODEX_SANDBOX_MODE="danger-full-access"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
  echo "[auto-develop $(date +%H:%M:%S)] $*"
}

die() {
  log "FATAL: $*" >&2
  exit 1
}

# Gate every privileged opt-in behind an explicit confirmation. A dry run never
# touches anything, so it is exempt. With --yes (or no TTY + --yes) the prompt is
# skipped; without a TTY and without --yes we refuse rather than block forever.
confirm_privileged_mode() {
  [[ "$DRY_RUN" == true ]] && return 0

  local -a privileged=()
  [[ "$CLAUDE_PERMISSION_MODE" == "bypassPermissions" ]] && \
    privileged+=("Claude runs with --permission-mode=bypassPermissions (no per-action approval)")
  [[ "$CODEX_SANDBOX_MODE" == "danger-full-access" ]] && \
    privileged+=("Codex reviewer runs with --sandbox=danger-full-access")
  [[ "$AUTO_MERGE" == true ]] && \
    privileged+=("PRs are squash-merged automatically after a clean review")

  [[ ${#privileged[@]} -eq 0 ]] && return 0   # fully safe defaults; nothing to confirm

  log "PRIVILEGED UNATTENDED MODE requested:"
  local item
  for item in "${privileged[@]}"; do log "  - $item"; done

  if [[ "$ASSUME_YES" == true ]]; then
    log "Confirmed via --yes."
    return 0
  fi
  if [[ ! -t 0 ]]; then
    die "Privileged mode needs confirmation but no TTY is attached. Re-run with --yes."
  fi

  local reply=""
  read -r -p "Proceed in privileged unattended mode? [y/N] " reply || true   # EOF (Ctrl-D) -> empty -> abort cleanly below
  [[ "$reply" =~ ^[Yy]$ ]] || die "Aborted by operator."
}

build_reexec_args() {
  local -a args
  args+=(--max-issues "$MAX_ISSUES")
  [[ -n "$TARGET_ISSUE" ]] && args+=(--issue "$TARGET_ISSUE")
  args+=(--model "$MODEL")
  args+=(--review-a "$REVIEW_A_MODEL" --review-a-effort "$REVIEW_A_EFFORT")
  args+=(--review-b "$REVIEW_B_MODEL" --review-b-effort "$REVIEW_B_EFFORT")
  args+=(--max-rounds "$MAX_ROUNDS")
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
  [[ -n "${TMUX:-}" ]] && {
    log "Already inside tmux session '$TMUX_SESSION'; continuing in foreground."
    return 0
  }
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

# Map short model names to the IDs that `claude -p --model` expects.
resolve_claude_model() {
  case "$1" in
    sonnet) echo "claude-sonnet-4-6" ;;
    opus)   echo "claude-opus-4-6" ;;
    haiku)  echo "claude-haiku-4-5-20251001" ;;
    *)      echo "$1" ;;          # passthrough for full IDs
  esac
}

resolve_codex_model() {
  case "$1" in
    codex) echo "gpt-5.4" ;;
    codex-*) echo "$1" ;;
    gpt-*) echo "$1" ;;
    *) echo "$1" ;;
  esac
}

git_status_outside_logs() {
  git status --porcelain --untracked-files=all -- . ":(exclude)$LOGDIR"
}

has_repo_changes_outside_logs() {
  [[ -n "$(git_status_outside_logs)" ]]
}

require_clean_worktree() {
  if has_repo_changes_outside_logs; then
    log "Working tree has existing changes outside $LOGDIR. Refusing to mix them into auto-develop."
    git_status_outside_logs >&2
    return 1
  fi
}

stage_repo_changes() {
  git add -A -- . ":(exclude)$LOGDIR"
}

restore_branch() {
  local branch="$1"
  if ! git checkout "$branch" >/dev/null 2>&1; then
    log "Could not switch back to $branch automatically. Leaving current branch checked out."
  fi
}

# Run a prompt through the Claude CLI.
# Pipes prompt via stdin to avoid "Argument list too long" on large diffs.
run_claude_model() {
  local model_short="$1"
  local effort="$2"
  local prompt_file="$3"
  shift 3

  local model_id
  model_id="$(resolve_claude_model "$model_short")"
  if [[ -n "$effort" ]]; then
    cat "$prompt_file" | claude -p - \
      --model "$model_id" \
      --effort "$effort" \
      --permission-mode "$CLAUDE_PERMISSION_MODE" \
      --output-format text \
      "$@" 2>&1
  else
    cat "$prompt_file" | claude -p - \
      --model "$model_id" \
      --permission-mode "$CLAUDE_PERMISSION_MODE" \
      --output-format text \
      "$@" 2>&1
  fi
}

# Usage: run_model <short_model> <prompt_file>
#   prompt_file is a path whose contents are sent as the prompt.
run_model() {
  local model_short="$1"
  local prompt_file="$2"
  shift 2

  run_claude_model "$model_short" "" "$prompt_file" "$@" 2>&1
}

run_codex_model() {
  local model_name="$1"
  local effort="$2"
  local sandbox_mode="$3"
  local prompt_file="$4"
  shift 4

  local model_id
  local -a cmd

  model_id="$(resolve_codex_model "$model_name")"
  cmd=(
    codex
    exec
    --model "$model_id"
    --sandbox "$sandbox_mode"
  )

  if [[ -n "$effort" ]]; then
    cmd+=(-c "model_reasoning_effort=\"$effort\"")
  fi

  # Pass prompt via stdin (using '-') to avoid "Argument list too long" for large prompts.
  # codex exec treats '-' as the prompt argument and reads the actual content from stdin.
  cmd+=("-")

  cat "$prompt_file" | "${cmd[@]}" "$@" 2>&1
}

slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//' \
    | cut -c1-40
}

ensure_logdir() {
  local dir="$LOGDIR/$1"
  mkdir -p "$dir"
  echo "$dir"
}

# ---------------------------------------------------------------------------
# Issue helpers
# ---------------------------------------------------------------------------

issue_has_agent_auto() {
  local issue_number="$1"
  local count
  count="$(gh issue view "$issue_number" --json labels \
    --jq '[.labels[].name] | map(select(. == "agent:auto")) | length')"
  [[ "$count" -gt 0 ]]
}

check_dependencies() {
  local issue_number="$1"
  local body deps

  body="$(gh issue view "$issue_number" --json body --jq '.body')"
  deps="$(echo "$body" | grep -oiE 'depends on #[0-9]+' | grep -oE '[0-9]+' || true)"

  if [[ -z "$deps" ]]; then
    return 0
  fi

  for dep in $deps; do
    local state
    state="$(gh issue view "$dep" --json state --jq '.state')"
    if [[ "$state" != "CLOSED" ]]; then
      log "Blocked by #$dep (state: $state)"
      return 1
    fi
  done

  return 0
}

# ---------------------------------------------------------------------------
# Branch management
# ---------------------------------------------------------------------------

create_issue_branch() {
  local issue="$1"
  local title="$2"
  local slug branch

  slug="$(slugify "$title")"
  branch="issue-${issue}-${slug}"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout "$branch"
  else
    git checkout -b "$branch"
  fi
  echo "$branch"
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

run_checks() {
  local logfile="$1"
  local failed=false

  if [[ ! -f "package.json" ]]; then
    log "No package.json — skipping checks."
    echo "SKIP: no package.json" > "$logfile"
    return 0
  fi

  {
    echo "=== type-check ==="
    if ! pnpm type-check 2>&1; then failed=true; fi

    echo "=== lint ==="
    if ! pnpm lint 2>&1; then failed=true; fi

    echo "=== build ==="
    if ! pnpm build 2>&1; then failed=true; fi
  } > "$logfile"

  [[ "$failed" == false ]]
}

ensure_checks_pass() {
  local issue="$1"
  local logdir="$2"
  local prefix="$3"

  local checks_log="$logdir/${prefix}.log"
  local fix_prompt="$logdir/${prefix}-fix-prompt.txt"
  local fix_log="$logdir/${prefix}-fix.log"
  local rerun_log="$logdir/${prefix}-rerun.log"
  local check_output

  if run_checks "$checks_log"; then
    log "Checks passed."
    return 0
  fi

  log "Checks failed. Attempting auto-fix..."
  check_output="$(cat "$checks_log")"
  build_check_fix_prompt "$issue" "$check_output" "$fix_prompt"
  run_model "$MODEL" "$fix_prompt" > "$fix_log" 2>&1

  if run_checks "$rerun_log"; then
    log "Checks pass after fix."
    return 0
  fi

  log "Checks still failing after fix attempt. See $rerun_log"
  return 1
}

# ---------------------------------------------------------------------------
# Prompt builders (write to temp files to avoid quoting issues)
# ---------------------------------------------------------------------------

build_implementation_prompt() {
  local issue="$1" title="$2" body="$3" outfile="$4"

  cat > "$outfile" <<PROMPT
You are implementing issue #${issue} for the Prima Klima Reisen website project.

## Issue
**#${issue}: ${title}**

${body}

## Instructions
- Read SOUL.md and MEMORY.md before starting.
- Read the relevant section of payload-coolify-setup.md if applicable.
- Implement the requirements in small, testable steps.
- Follow TypeScript strict mode, Payload CMS 3.x patterns, and the coding standards in SOUL.md.
- Do NOT modify SOUL.md or AGENTS.md.
- In MEMORY.md "Next Up" section, add ONE status line: \`- #${issue} (${title}): implementing\`
- Do NOT write to the "Completed Work" section — the pipeline handles that after review.
- When done, ensure all files are saved. Do not commit — the pipeline handles that.
PROMPT
}

build_review_prompt() {
  local reviewer_label="$1" issue="$2" title="$3" body="$4" diff="$5" file_tree="$6" outfile="$7"

  # Role-specific focus areas
  local role_focus=""
  if [[ "$reviewer_label" == *"Opus"* ]]; then
    role_focus="Your focus as Reviewer A:
- **Correctness**: Does the code do what the issue requires? Are there logic errors?
- **Security**: Do public routes have validation, origin checks, and rate limiting? Are secrets kept out of code? Is whistleblower content encrypted properly (AES-256-GCM, random 12-byte IV, never persisted decrypted)?
- **Architecture**: Does this fit the project structure? Is Payload used correctly (runs inside Next.js, not separate)? Are blocks colocated with their renderers?
- **TypeScript quality**: Strict mode respected? No unjustified \`any\`? Named exports used?
- **Payload patterns**: Frontend queries use \`overrideAccess: false\`? Localization handled correctly (German default, English under /en/, fallback: false at config level)?"
  elif [[ "$reviewer_label" == *"Codex"* ]]; then
    role_focus="Your focus as Reviewer B:
- **Issue coverage**: Are ALL requirements from the issue body addressed? Nothing skipped or partially done?
- **Regressions**: Could these changes break existing functionality? Are imports and exports consistent with the rest of the codebase?
- **Practical review**: Does the code actually work? Are there missing dependencies, wrong paths, typos, or dead code?
- **File hygiene**: No unnecessary files created? No unrelated changes mixed in? Config files consistent?
- **Edge cases**: Are error states handled? Are there obvious failure modes not covered?"
  fi

  cat > "$outfile" <<PROMPT
You are ${reviewer_label} reviewing implementation work for issue #${issue}.

## Issue
**#${issue}: ${title}**

${body}

## Project context

### Stack
- Next.js 16+ (App Router, SSG/ISR) with Payload CMS 3.x integrated (single deployment, not separate)
- PostgreSQL 16, TypeScript strict mode, Tailwind CSS, Lexical for rich text
- Hosting: Hetzner Cloud + Docker + Coolify (behind Traefik)

### Coding standards
- TypeScript strict mode. No \`any\` without clear reason.
- Prefer named exports.
- Keep block definitions and renderers colocated by name.
- Use \`next/image\` for site images with proper \`sizes\`.
- Frontend Payload queries must use \`overrideAccess: false\`.
- Use structured error codes for public APIs.
- German is default locale (no prefix); English under \`/en/\`.
- Localization fallback is \`false\` at config level.

### Security principles
- No secrets in code, commits, or tracked files.
- Whistleblower content: AES-256-GCM encryption at rest, random 12-byte IV per operation, never persist decrypted.
- All public POST routes: validation, origin checks, rate limiting.
- Use \`timingSafeEqual\` for token comparisons.
- Sanitize filenames, restrict MIME types for uploads.

### Prohibited actions
- No secrets or credentials in tracked files.
- No plaintext whistleblower content in files or logs.
- No privileged Payload access (\`overrideAccess: true\`) in frontend queries unless explicitly documented.
- No disabling rate limiting or origin checks for convenience.

## ${role_focus}

## Current file tree (for context)
\`\`\`
${file_tree}
\`\`\`

## Diff to review
\`\`\`diff
${diff}
\`\`\`

## Review checklist
- [ ] All requirements from the issue are fully addressed
- [ ] No prohibited actions were taken
- [ ] Security principles are satisfied
- [ ] Public routes include validation and abuse protections where applicable
- [ ] No secrets or sensitive plaintext introduced
- [ ] Code follows TypeScript strict mode and project coding standards
- [ ] Implementation is consistent with payload-coolify-setup.md patterns

## Review rules
- This is a READ-ONLY review. Do NOT edit any files.
- If something is unclear or incomplete, reject it — do not silently accept.
- Only flag real issues. Do not nitpick formatting that linters handle.
- Consider whether changes could break existing functionality.

## Output format
If everything looks good, respond with exactly: LGTM

If there are findings, respond with a numbered list:
1. [SEVERITY] file:line - description
   (SEVERITY is one of: CRITICAL, HIGH, MEDIUM, LOW)

End with a summary line: FINDINGS: <count>
PROMPT
}

build_fix_prompt() {
  local issue="$1" title="$2" body="$3"
  local findings_a="$4" findings_b="$5" round="$6" outfile="$7"

  local review_a_content review_b_content
  review_a_content="$(cat "$findings_a" 2>/dev/null || echo "(no findings)")"
  review_b_content="$(cat "$findings_b" 2>/dev/null || echo "(no findings)")"

  cat > "$outfile" <<PROMPT
You are fixing review findings for issue #${issue}.

## Issue
**#${issue}: ${title}**

${body}

## Reviewer A findings
${review_a_content}

## Reviewer B findings
${review_b_content}

## Instructions
- Address all CRITICAL and HIGH findings. Address MEDIUM findings if straightforward.
- Read SOUL.md for project standards.
- Do NOT modify SOUL.md or AGENTS.md.
- In MEMORY.md "Next Up" section, OVERWRITE the status line for this issue with: \`- #${issue}: review round ${round}, fixing: <brief description of what you fixed>\`
- Do NOT add review cycle details to "Completed Work". Do NOT append — overwrite the single status line.
- When done, ensure all files are saved. Do not commit.
PROMPT
}

build_memory_update_prompt() {
  local issue="$1" title="$2" round="$3" outfile="$4"

  cat > "$outfile" <<PROMPT
Update memory files for completed issue #${issue}.

## Task
1. Add a ONE-LINE entry to \`memory/completed-phases.md\` under the appropriate phase heading.
2. Remove any status line for #${issue} from "Next Up" in MEMORY.md.
3. Do NOT add issue details to MEMORY.md — only update "Next Up" and blockers there.

Format for completed-phases.md: \`- ${title} (#${issue}): <brief what was built>. Last fix: <what the final review fix addressed>\`

Rules:
- Maximum 1-2 lines per entry. Be concise.
- Include "Last fix: ..." only if review rounds > 1 (this issue had ${round} rounds).
- Do NOT document individual review cycles or reviewer names.
- Do NOT list accepted deviations unless they affect future development.
- Do NOT modify SOUL.md or AGENTS.md.
- MEMORY.md stays lean: only current state and open decisions. See Update Rules in MEMORY.md.
PROMPT
}

build_check_fix_prompt() {
  local issue="$1" check_output="$2" outfile="$3"

  cat > "$outfile" <<PROMPT
The implementation for issue #${issue} has failing checks. Fix them.

## Check output
${check_output}

## Instructions
- Fix the failing checks (type-check, lint, build).
- Read SOUL.md for coding standards.
- Do NOT modify SOUL.md or AGENTS.md.
- Do not commit.
PROMPT
}

# ---------------------------------------------------------------------------
# Pipeline phases
# ---------------------------------------------------------------------------

run_implementation() {
  local issue="$1" title="$2" body="$3" logdir="$4"
  local prompt_file="$logdir/prompt-impl.txt"

  build_implementation_prompt "$issue" "$title" "$body" "$prompt_file"

  log "Running implementation with model=$MODEL..."
  run_model "$MODEL" "$prompt_file" > "$logdir/01-implementation.log" 2>&1
  local rc=$?
  log "Implementation finished (exit=$rc)."
  return $rc
}

run_review() {
  local reviewer_label="$1" reviewer_model="$2" reviewer_effort="$3"
  local issue="$4" title="$5" body="$6" logfile="$7" logdir="$8"

  local diff
  # Use 'git diff master' (not master..HEAD) to include uncommitted working-tree
  # changes from fix cycles — otherwise reviewers re-review the stale committed
  # diff and the pipeline loops forever.
  # Exclude MEMORY.md — reviewers don't need it and it bloats the context
  # (status lines grow each fix cycle, causing context overflow).
  diff="$(git diff master -- . ':!MEMORY.md' 2>/dev/null || true)"

  if [[ -z "$diff" ]]; then
    log "No diff to review for $reviewer_label."
    echo "LGTM (no changes to review)" > "$logfile"
    return 0
  fi

  # Build file tree for context (src/ and config files, max 80 lines)
  local file_tree
  file_tree="$(find . -maxdepth 4 \( -path './node_modules' -o -path './.git' -o -path './.next' -o -path './logs' \) -prune -o -type f -print | sort | head -80 2>/dev/null || echo '(unavailable)')"

  local prompt_file
  prompt_file="$logdir/prompt-review-$(echo "$reviewer_label" | tr ' ()' '---').txt"
  build_review_prompt "$reviewer_label" "$issue" "$title" "$body" "$diff" "$file_tree" "$prompt_file"

  log "Running $reviewer_label review with model=$reviewer_model..."
  if [[ "$reviewer_label" == "Reviewer B (Codex)" ]]; then
    run_codex_model "$reviewer_model" "$reviewer_effort" "$CODEX_SANDBOX_MODE" "$prompt_file" > "$logfile" 2>&1
  else
    run_claude_model "$reviewer_model" "$reviewer_effort" "$prompt_file" > "$logfile" 2>&1
  fi
  local rc=$?
  log "$reviewer_label review finished (exit=$rc)."

  # LGTM anywhere in output = pass
  if grep -qi "^LGTM" "$logfile" 2>/dev/null; then
    return 0
  fi
  return 1
}

run_fix_cycle() {
  local issue="$1" title="$2" body="$3"
  local findings_a="$4" findings_b="$5" logdir="$6" round="$7"
  local prompt_file="$logdir/prompt-fix-r${round}.txt"

  build_fix_prompt "$issue" "$title" "$body" "$findings_a" "$findings_b" "$round" "$prompt_file"

  log "Running fix cycle (round $round) with model=$MODEL..."
  run_model "$MODEL" "$prompt_file" > "$logdir/04-fix-r${round}.log" 2>&1
  local rc=$?
  log "Fix cycle finished (exit=$rc)."
  return $rc
}

# ---------------------------------------------------------------------------
# Main pipeline for one issue
# ---------------------------------------------------------------------------

process_issue() {
  local issue="$1"
  local title body logdir branch

  if ! require_clean_worktree; then
    return 1
  fi

  title="$(gh issue view "$issue" --json title --jq '.title')"
  body="$(gh issue view "$issue" --json body --jq '.body')"
  logdir="$(ensure_logdir "$issue")"

  log "=========================================="
  log "Pipeline start: #$issue — $title"
  log "  model=$MODEL  review-a=$REVIEW_A_MODEL  review-a-effort=$REVIEW_A_EFFORT  review-b=$REVIEW_B_MODEL  review-b-effort=$REVIEW_B_EFFORT"
  log "=========================================="

  # Save current branch so we can return on failure
  local original_branch
  original_branch="$(git branch --show-current)"

  # Create issue branch
  branch="issue-${issue}-$(slugify "$title")"
  create_issue_branch "$issue" "$title" >/dev/null
  log "Branch: $branch"

  # --- Phase 1: Implementation ------------------------------------------------
  if ! run_implementation "$issue" "$title" "$body" "$logdir"; then
    log "Implementation failed. See $logdir/01-implementation.log"
    restore_branch "$original_branch"
    return 1
  fi

  # --- Phase 2: Checks --------------------------------------------------------
  if ! ensure_checks_pass "$issue" "$logdir" "02-checks"; then
    log "Stopping pipeline because checks are still failing."
    restore_branch "$original_branch"
    return 1
  fi

  # --- Phase 3: Review loop ---------------------------------------------------
  local round=1
  local review_passed=false

  while [[ "$round" -le "$MAX_ROUNDS" ]]; do
    log "--- Review round $round/$MAX_ROUNDS ---"

    local review_a_log="$logdir/03-review-a-r${round}.log"
    local review_b_log="$logdir/03-review-b-r${round}.log"
    local review_a_pass=true
    local review_b_pass=true

    # Reviewer A (Opus)
    if ! run_review "Reviewer A (Opus)" "$REVIEW_A_MODEL" \
        "$REVIEW_A_EFFORT" "$issue" "$title" "$body" "$review_a_log" "$logdir"; then
      review_a_pass=false
    fi

    # Reviewer B (Codex)
    if ! run_review "Reviewer B (Codex)" "$REVIEW_B_MODEL" \
        "$REVIEW_B_EFFORT" "$issue" "$title" "$body" "$review_b_log" "$logdir"; then
      review_b_pass=false
    fi

    if [[ "$review_a_pass" == true && "$review_b_pass" == true ]]; then
      log "Both reviewers passed (LGTM)."
      review_passed=true
      break
    fi

    if [[ "$round" -ge "$MAX_ROUNDS" ]]; then
      log "Max review rounds ($MAX_ROUNDS) reached with unresolved findings."
      restore_branch "$original_branch"
      return 1
    fi

    # Snapshot code diff before fix (excluding MEMORY.md and logs)
    local diff_before_fix
    diff_before_fix="$(git diff master -- . ':!MEMORY.md' ':!logs/' 2>/dev/null | md5sum | cut -d' ' -f1)"

    # Fix cycle based on findings
    run_fix_cycle "$issue" "$title" "$body" \
      "$review_a_log" "$review_b_log" "$logdir" "$round"

    # Check if fix cycle changed any code (not just MEMORY.md)
    local diff_after_fix
    diff_after_fix="$(git diff master -- . ':!MEMORY.md' ':!logs/' 2>/dev/null | md5sum | cut -d' ' -f1)"

    if [[ "$diff_before_fix" == "$diff_after_fix" ]]; then
      log "Fix cycle produced no code changes (only MEMORY.md/logs). Remaining findings are accepted deviations."
      review_passed=true
      break
    fi

    # Re-run checks after fix
    if ! ensure_checks_pass "$issue" "$logdir" "02-checks-r${round}"; then
      log "Stopping pipeline because checks failed after review fixes."
      restore_branch "$original_branch"
      return 1
    fi

    round=$((round + 1))
  done

  # --- Phase 4: Update MEMORY.md with final summary ----------------------------
  if [[ "$review_passed" == true ]]; then
    log "Updating MEMORY.md with final summary..."
    local memory_prompt="$logdir/prompt-memory-update.txt"
    build_memory_update_prompt "$issue" "$title" "$round" "$memory_prompt"
    run_model "$MODEL" "$memory_prompt" > "$logdir/04-memory-update.log" 2>&1
  fi

  # --- Phase 5: Commit, push, PR ----------------------------------------------
  if [[ "$review_passed" != true ]]; then
    log "Stopping pipeline because reviewer findings remain unresolved."
    restore_branch "$original_branch"
    return 1
  fi

  if ! has_repo_changes_outside_logs; then
    log "No changes were produced for #$issue. Skipping commit."
    restore_branch "$original_branch"
    return 1
  fi

  log "Staging and committing..."
  stage_repo_changes
  git commit -m "$(cat <<EOF
feat: implement #${issue} - ${title}

Automated implementation via auto-develop.sh.
Model: ${MODEL} | Review A: ${REVIEW_A_MODEL} | Review B: ${REVIEW_B_MODEL}
Review A effort: ${REVIEW_A_EFFORT}
Review B effort: ${REVIEW_B_EFFORT}
Review rounds: ${round}/${MAX_ROUNDS} | Clean: ${review_passed}

Closes #${issue}
EOF
)"

  log "Pushing branch..."
  git push -u origin "$branch"

  log "Creating pull request..."
  gh pr create \
    --title "#${issue}: ${title}" \
    --body "$(cat <<EOF
## Issue
Closes #${issue}

## Pipeline
- **Implementation model:** \`${MODEL}\`
- **Reviewer A:** \`${REVIEW_A_MODEL}\`
- **Reviewer A effort:** \`${REVIEW_A_EFFORT}\`
- **Reviewer B:** \`${REVIEW_B_MODEL}\`
- **Reviewer B effort:** \`${REVIEW_B_EFFORT}\`
- **Review rounds:** ${round}/${MAX_ROUNDS}
- **Clean review:** ${review_passed}

## Logs
See \`logs/issues/${issue}/\` for full pipeline output.
EOF
)" 2>&1 | tee "$logdir/05-pr.log"

  if [[ "$AUTO_MERGE" != true ]]; then
    log "PR opened for #$issue. Auto-merge is OFF (enable with --auto-merge); stopping for human review."
    restore_branch "$original_branch"
    log "=== Pipeline complete for #$issue (PR awaiting review) ==="
    return 0
  fi

  log "Merging pull request..."
  if ! gh pr merge "$branch" --squash 2>&1 | tee -a "$logdir/06-merge.log"; then
    log "ERROR: Merge failed for #$issue. See $logdir/06-merge.log"
    restore_branch "$original_branch"
    return 1
  fi

  # Delete remote branch via GitHub API (git push --delete fails with token auth)
  gh api -X DELETE "repos/{owner}/{repo}/git/refs/heads/$branch" >/dev/null 2>&1 || true

  log "Updating master after merge..."
  git checkout master 2>/dev/null
  git pull origin master 2>/dev/null

  log "=== Pipeline complete for #$issue ==="
  return 0
}

# ---------------------------------------------------------------------------
# Candidate selection
# ---------------------------------------------------------------------------

if [[ -n "$TARGET_ISSUE" ]]; then
  if ! issue_has_agent_auto "$TARGET_ISSUE"; then
    log "Issue #$TARGET_ISSUE does not have the agent:auto label. Skipping."
    exit 1
  fi
  CANDIDATES=("$TARGET_ISSUE")
else
  mapfile -t CANDIDATES < <(
    gh issue list --label "agent:auto" --state open --limit 200 --json number --jq '.[].number' \
      | sort -n \
      | head -n 200
  )
fi

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
  log "No open issues with label agent:auto found."
  exit 0
fi

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

COMPLETED=0

for issue in "${CANDIDATES[@]}"; do
  if [[ "$COMPLETED" -ge "$MAX_ISSUES" ]]; then
    break
  fi

  log "Evaluating issue #$issue..."

  if ! check_dependencies "$issue"; then
    log "Skipping #$issue because dependencies are still open."
    continue
  fi

  if [[ "$DRY_RUN" == true ]]; then
    TITLE="$(gh issue view "$issue" --json title --jq '.title')"
    log "[dry-run] Would process #$issue — $TITLE"
    log "  model=$MODEL  review-a=$REVIEW_A_MODEL  review-a-effort=$REVIEW_A_EFFORT  review-b=$REVIEW_B_MODEL  review-b-effort=$REVIEW_B_EFFORT  max-rounds=$MAX_ROUNDS"
    COMPLETED=$((COMPLETED + 1))
    continue
  fi

  if process_issue "$issue"; then
    COMPLETED=$((COMPLETED + 1))
  else
    log "Issue #$issue produced no changes or failed."
  fi
done

log "Done. Completed $COMPLETED issue(s)."
