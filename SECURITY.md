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
  auto-merge) **off by default**, behind explicit user opt-in. Patterns that could weaken that
  default are in scope.
- `examples/auto-develop.payload-sample.sh` is a read-only sample carrying that project's opt-in
  privileged settings and must not be run in this repo.

## Supported versions

The latest release is supported.

| Version | Supported |
|---|---|
| 1.1.x | ✅ |
