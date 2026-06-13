# Repository Guidelines

## Project Structure & Module Organization
This repository is currently in bootstrap state. At the moment, the only tracked project artifact is `.claude/settings.local.json`, which contains local tooling permissions. No `src/`, `tests/`, `public/`, or `scripts/` directories exist yet. When adding implementation code, keep the root clean and introduce a predictable layout such as `src/` for application code, `tests/` for automated checks, and `docs/` for supporting documentation.

## Build, Test, and Development Commands
No build, test, lint, or local-run commands are configured yet. Before adding features, define project scripts in the relevant build file and keep them documented here. For current repository inspection, use `Get-ChildItem -Force` to view the workspace and `rg --files -uu` to list all files, including hidden ones.

## Coding Style & Naming Conventions
Match the style of the files you touch. Since the repo currently contains only JSON and Markdown, use consistent formatting with concise comments and descriptive names. Prefer lowercase, hyphenated Markdown filenames such as `contributor-guide.md`, and keep configuration files readable with stable key ordering where possible.

## Testing Guidelines
There is no test framework configured yet. Add tests alongside the first real code contribution and place them in a dedicated `tests/` directory or next to the modules they verify. Name test files after the unit under test, for example `auth.test.ts` or `api_client_test.py`, and document the test command in this guide once introduced.

## Commit & Pull Request Guidelines
This workspace is not currently initialized as a Git repository, so there is no commit history to infer conventions from. Use Conventional Commit prefixes such as `feat:`, `fix:`, `docs:`, and `chore:` once Git is enabled. Pull requests should include a short purpose statement, a summary of changed files, setup or verification notes, and screenshots only when UI work is added later.

## Security & Configuration Tips
Treat `.claude/settings.local.json` as local tooling configuration, not application logic. Do not commit secrets, tokens, or machine-specific credentials. Keep environment-specific values in untracked local files once runtime configuration is introduced.
