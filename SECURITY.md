# Security Policy

## Reporting a vulnerability

Please report security issues **privately** via GitHub's
[Private vulnerability reporting](https://github.com/Karlderkarl/governance-to-automation/security/advisories/new)
(repository **Security** tab → *Report a vulnerability*). Do **not** open a public issue for a
security report.

We aim to acknowledge a report within a few days and will coordinate a fix and disclosure with you.

## Scope

This repository ships a Claude Code **skill** (Markdown instructions + reference blueprints) plus an
example Bash script. The skill *generates* automation for other projects; it does not perform
privileged operations itself. Of particular interest:

- The generated `auto-develop.sh` keeps privileged flags (`bypassPermissions`, `danger-full-access`,
  auto-merge) **off by default**: safe modes are shipped, the privileged values are never hardcoded,
  and they are reached only via the `--unattended` / `--auto-merge` flags behind a runtime
  `confirm_privileged_mode` gate (prompts `[y/N]`, refuses without a TTY unless `--yes` is given).
  Patterns that could weaken that default — hardcoding a privileged mode, bypassing the gate, or
  letting the `tmux` re-exec auto-`--yes` without a prior foreground confirmation — are in scope.
- `examples/auto-develop.payload-sample.sh` is a read-only sample that mirrors the same
  safe-by-default policy and must not be run in this repo.
- The generated targeted-test gate substitutes a **model-authored** `{TARGET}` value into a command
  run via `bash -c` (not `eval`). The template sanitizes it against a strict allowlist
  (`^[][A-Za-z0-9_./:@=+#-]+$`) before substitution, rejecting any shell metacharacters. Patterns
  that would weaken that sanitization, or otherwise let model-authored input reach a shell
  unescaped, are in scope.

## Known scanner findings

The pipeline runs project commands through a shell (`bash -c "$cmd"`), which static scanners may flag
under an OS-command-injection heuristic. `eval` was deliberately replaced by `bash -c` to clear the
stricter `eval`-specific rule; the dynamic-execution itself is intended and mitigated, not an
exploitable issue:

- `run_checks` runs each entry of `CHECKS[]` via `bash -c`. `CHECKS[]` is **governance-authored** —
  the project's own `CLAUDE.md` validation commands are the only source of the toolchain, and a
  stack-agnostic pipeline must run arbitrary command strings (`a | b`, `cd x && y`) verbatim. This
  input is trusted by construction.
- The targeted-test gate runs a command built from a **model-authored** `{TARGET}`, but that value
  is sanitized against a strict allowlist (`^[][A-Za-z0-9_./:@=+#-]+$`) **before** substitution (see
  *Scope* above), so no shell metacharacters can reach the shell.

Reports that demonstrate a way *past* the `{TARGET}` allowlist, or that the `CHECKS[]` input can be
influenced by an untrusted party, are in scope and welcome. A generic "runs a shell command" scanner
label, absent such a path, is expected and accepted.

## Supported versions

The latest release is supported.

| Version | Supported |
|---|---|
| 1.2.x | ✅ |
