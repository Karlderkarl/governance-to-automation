# Governance Skills

Skills for turning project requirements into governance files and then turning that governance
into an automated implementation pipeline.

## Skills

- `prd-to-governance`
  Create, update, and audit `SOUL.md`, `AGENTS.md`, `CLAUDE.md`, and `MEMORY.md` from a PRD and the current repository state.
- `governance-to-automation`
  Generate and keep in sync an issue-driven `auto-develop.sh` pipeline plus its task source, prompt builders, and logging from existing governance.

## Install

Install the whole repository:

```bash
npx skills add Karlderkarl/governance-to-automation
```

List available skills first:

```bash
npx skills add Karlderkarl/governance-to-automation --list
```

Install one specific skill:

```bash
npx skills add Karlderkarl/governance-to-automation --skill prd-to-governance
npx skills add Karlderkarl/governance-to-automation --skill governance-to-automation
```

## Repository Layout

The skill definitions live in `.agents/skills/`:

- `.agents/skills/prd-to-governance/SKILL.md`
- `.agents/skills/governance-to-automation/SKILL.md`

Supporting reference material is stored next to each skill in its `references/` directory.
