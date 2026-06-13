<!--
  EXAMPLE / SAMPLE — not this repository's task list.
  A worked instance of the local task-list source (Option B) from
  .agents/skills/governance-to-automation/references/task-list-template.md,
  for a Node/pnpm + Payload CMS project. Kept as a format fixture only.
  `status:` values shown all done to illustrate a completed pass.
-->

# Payload-Sample Task List

## Priority 1

### 1. `MEMORY.md` konsolidieren
Statuszeilen zusammenführen, Verlauf ins Archiv auslagern.
- depends on: none
- status: done        <!-- open | doing | done -->

### 2. PNPM-Version pinnen
`packageManager` in `package.json` festschreiben, corepack-konform.
- depends on: none
- status: done

### 3. `not-found.tsx` warnings-frei machen
Build-Warnungen der 404-Route beseitigen.
- depends on: none
- status: done

## Priority 2

### 4. `RESERVED_SLUGS` zentralisieren
Verstreute Slug-Konstanten in ein Modul ziehen.
- depends on: 3
- status: done

### 5. gemeinsame Page-/Metadata-Helfer extrahieren
Doppelte Metadata-Logik in geteilte Helfer überführen.
- depends on: 4
- status: done

## Priority 3

### 6. Generated Payload Types konsequenter nutzen
Hand-getippte Casts durch generierte Typen ersetzen.
- depends on: none
- status: done

### 7. `postinstall` in eigenes Script auslagern
`postinstall`-Logik in ein versioniertes Script verschieben.
- depends on: none
- status: done

## Packages

| Package | Tasks | Effort |
|---|---|---|
| Minimal clean | 1-3 | 1-2 h |
| Sensible block | 1-5 | 4-6 h |
| Full pass | 1-7 | 6-8 h |

## Post-package checks
After each package, run the project checks:
- `corepack pnpm type-check`
- `corepack pnpm lint`
- quick visual check of the touched routes/files
