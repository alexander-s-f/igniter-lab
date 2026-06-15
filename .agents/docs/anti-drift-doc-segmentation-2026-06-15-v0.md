# Anti-Drift Document Segmentation Protocol — 2026-06-15 v0

## Problem

Agents searching the workspace pick up too many operational rollups, stale daily
plans, and historical wave summaries. That creates drift: a grep meant to find canon
or current state returns hundreds of old coordination artifacts.

## Decision

Separate documentation by authority and recency.

- Canon/spec material stays in `igniter-lang`.
- Lab proof evidence stays in `igniter-lab/lab-docs` and cards.
- Active operations stay in `igniter-lab/.agents/docs` only while they are the current
  crest of the wave.
- Older operational docs move to `igniter-lab/.agents/docs/archive/operational`.
- Private cross-track memory stays in `igniter-gov/portfolio/governance`.

## Active Crest Rule

`igniter-lab/.agents/docs` should contain only:

1. latest one or two app recheck rollups;
2. latest daily checkpoint;
3. active doc hygiene / operating protocol docs;
4. lightweight indexes pointing to archives.

Everything older is evidence, not active navigation.

## Archive Rule

Archive by month and category:

```text
igniter-lab/.agents/docs/archive/operational/YYYY-MM/app-rechecks/
igniter-lab/.agents/docs/archive/operational/YYYY-MM/daily/
```

Archive moves must preserve filenames. Do not rewrite historical docs during moves.
If a historical doc contains a stale claim, create a current crest note instead of
mutating history.

## Canon Boundary

Never move canon docs into lab archive:

- `igniter-lang/docs/**`
- `igniter-lang/.agents/work/proposals/**`
- accepted PROPs
- spec chapters

These are authority or proposal surfaces. If they drift, fix or supersede them in
place through the normal proposal/spec path.

## Lab Evidence Boundary

Do not archive proof docs/cards merely because they are old:

- `igniter-lab/lab-docs/**`
- `igniter-lab/.agents/work/cards/**`
- proof runners

They are evidence surfaces and dispatch state. Archive only operational rollups under
`.agents/docs` unless a separate card authorizes broader cleanup.

## Agent Search Protocol

1. For current state: search active crest + proposal README/card indexes first.
2. For canon: search `igniter-lang/docs` and `igniter-lang/.agents/work/proposals`.
3. For lab evidence: search `igniter-lab/lab-docs` and card files.
4. For historical deltas: search `.agents/docs/archive` and `igniter-gov`.
5. Treat daily/checkpoint docs as coordination memory, not implementation authority.

## Closed Surfaces

- No canon docs moved.
- No lab proof docs moved.
- No card/proposal history rewritten.
- No git history rewrite.
- No deletion of operational evidence.
