# LAB-HYGIENE-STALE-PATHS-README-P1 - refresh workspace path maps after domain rehome

Status: CLOSED
Lane: workspace hygiene / docs
Type: documentation cleanup
Delegation code: OPUS-HYGIENE-STALE-PATHS-README-P1
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Gemini drift forensics found stale path maps after the lab rehome into domain umbrellas.

Known stale surfaces:

- `/Users/alex/dev/projects/igniter-workspace/README.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-lab-value-transfer.md`

Examples: docs still list `igniter-lab/igniter-compiler`, `igniter-lab/igniter-vm`,
`igniter-lab/igniter-view-engine`, etc. Live shape is now `lang/`, `runtime/`, `server/`, `frame-ui/`,
`ide/`, `apps/`, `archive/`.

## Goal

Update only stale path mapping prose so agents stop opening pre-rehome paths.

## Verify first

Run/read:

```text
find /Users/alex/dev/projects/igniter-workspace/igniter-lab -maxdepth 2 -type d
sed -n '55,90p' /Users/alex/dev/projects/igniter-workspace/README.md
sed -n '45,90p' /Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-lab-value-transfer.md
```

Use live directories as authority. Do not infer from old docs.

## Acceptance

- [x] `README.md` lists current lab domain umbrellas and key child paths.
- [x] `igniter-lab-value-transfer.md` no longer presents flat pre-rehome targets as current targets.
- [x] Historical transfer meaning is preserved where useful; stale current-path wording is removed or clearly marked historical.
- [x] No code changes.
- [x] No file moves/deletes.
- [x] `git diff --check` clean.

## Closing Notes

- Verified live lab directories with `find /Users/alex/dev/projects/igniter-workspace/igniter-lab -maxdepth 2 -type d`.
- Updated `/Users/alex/dev/projects/igniter-workspace/README.md` so `igniter-lab` points agents to current domain umbrellas: `lang/`, `runtime/`, `server/`, `frame-ui/`, `ide/`, `apps/`, `archive/`, `lab-docs/`, `tools/`, and `.agents/`.
- Updated `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-lab-value-transfer.md` so historical source paths remain historical, while target paths use the current umbrella layout.
- Verification: `git diff --check`.

## Closed scope

No broad README rewrite, no roadmap changes, no card renames, no Cargo workspace changes.

## Next

After this, `LAB-HYGIENE-STATUS-CLEAN-P2`.
