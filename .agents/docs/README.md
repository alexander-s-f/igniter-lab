# Igniter Lab Agent Docs

This directory is an active navigation surface for lab operations. It is not canon
language authority.

## Active Crest

Keep only current-wave documents here:

- latest app-pressure recheck rollups;
- latest daily checkpoint;
- active hygiene/protocol documents;
- short indexes that point to archived evidence.

Historical operational wave docs move to `archive/operational/` so agent search does
not drown in stale rollups.

## Categories

| Category | Location | Authority |
|---|---|---|
| Canon spec/proposals | `igniter-lang/docs`, `igniter-lang/.agents/work/proposals` | Canon or proposal authority, depending on status |
| Lab proof docs/cards | `igniter-lab/lab-docs`, `igniter-lab/.agents/work/cards` | Lab evidence / dispatch state |
| Active operations | `igniter-lab/.agents/docs` | Current navigation only |
| Archived operations | `igniter-lab/.agents/docs/archive/operational` | Historical evidence, not active search target |
| Private governance checkpoints | `igniter-gov/portfolio/governance` | Private cross-track memory |

## Search Discipline

For active decisions, search active crest first. Search archives only when you need
historical evidence, old wave deltas, or a prior daily checkpoint.

Suggested active search:

```bash
rg "TERM" igniter-lang/docs igniter-lang/.agents/work/proposals \
  igniter-lab/lab-docs igniter-lab/.agents/docs \
  igniter-lab/.agents/work/cards
```

Suggested historical search:

```bash
rg "TERM" igniter-lab/.agents/docs/archive igniter-gov/portfolio/governance
```
