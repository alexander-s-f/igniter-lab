# LAB-AUDIT-CONTROL-BOARD-EXIT-REFRESH-P40

Status: OPEN
Route: standard / main-audit / control-board / exit-readiness
Skill: idd-agent-protocol
Depends-On:
- `LAB-IGNITER-WEB-LIVE-BIND-HUMAN-GATED-PROOF-P39`

## Goal

After P39 lands, refresh the audit control board and implemented-surface pointers
so the team has one clear answer to: "are we done with the foundation-audit
digestion wave, and what remains deliberately deferred?"

This is a **doc-only control pass**. It should not implement new foundations and
must not reopen closed rows from historical audit packets without fresh live
evidence.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- any package-local `IMPLEMENTED_SURFACE.md` files touched since the last audit
  refresh;
- P39 proof packet;
- current `git log --oneline` for the latest audit commits;
- current open card list in `.agents/work/cards/lang/`.

## Scope

Allowed:

- Update only the audit board, current wave/index docs, and implemented-surface
  docs that are stale against live source.
- Reclassify rows as `CLOSED`, `PARTLY CLOSED`, `DEFERRED`, or `QUEUED` based on
  live proof.
- Create a short exit packet if useful, naming exactly which issues are no
  longer blockers and which lanes remain intentionally outside the audit wave.
- Identify duplicates/stale cards that should not be re-dispatched.

Closed:

- Do not edit production code.
- Do not broaden into Todo API, frame-ui, science, TBackend, or command-center
  product work.
- Do not mark a row `CLOSED` based only on old proof docs if current live source
  disagrees.
- Do not change canon/governance claims.

## Questions To Answer

1. After P39, does A10 become `CLOSED for lab proof` or remain `PARTLY CLOSED`
   with a production-hosting follow-up?
2. Are A12, A22, and A24 still intentionally deferred/parallel, or did current
   source make them stale?
3. Are there any remaining `Blocker` or `Safety` rows without a named owner lane?
4. Which old cards/docs should agents stop citing as blockers?
5. What is the next non-audit wave recommendation?

## Acceptance

- [ ] P39 result is read and reflected accurately.
- [ ] `lab-audit-control-board-v1.md` is updated only where live truth changed.
- [ ] Any changed `IMPLEMENTED_SURFACE.md` file is verified against source.
- [ ] Remaining deferred/parallel rows have clear owner lanes and are not
      blocking audit exit.
- [ ] No production code changes.
- [ ] `git diff --check` passes.
- [ ] Card closed with concise report.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
git status --short
git diff --check
```

If an implemented-surface script exists for a touched package, run it.

## Optional Packet

Create only if the findings need more than the board row:

```text
lab-docs/lang/lab-audit-exit-refresh-p40-v0.md
```

The packet should be short: exit status, remaining deferred lanes, stale-card
warnings, and recommended next wave.
