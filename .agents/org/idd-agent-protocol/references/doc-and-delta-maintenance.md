# Doc, Delta & Map Maintenance

Use this reference when the work is *maintaining the documentation system itself*
in an Igniter workspace (canon / lab / gov), not shipping a feature.

It adds three maintenance artifacts to the artifact ladder and one anti-pattern.

## The system in one paragraph

A workspace has **one MAP per repo** (navigation only, ~1 screen; everything else
is a sub-index reachable from it), **three living documents** that are *updated in
place, never snapshotted* (canon↔lab delta ledger, per-repo status boards, the doc
segmentation standard), and a **segmentation standard** that decides what is hot /
archive / cold. Dated reports and daily checkpoints are *outputs* that cite the
living docs — they are not the source of truth.

## Maintenance artifacts (smallest-first)

| artifact | use when | not for |
|---|---|---|
| **ledger row edit** | a gate closed, proof landed, conformance claim | writing a new standalone delta doc |
| **map edit** | a canonical path moved / category added / MAP > 1 screen | re-homing the target docs |
| **segmentation sweep** | an operational area outgrew its crest | canon or lab-evidence docs |

Dispatch forms live in `igniter-gov/cards/` (`ledger-reconcile`,
`map-maintenance`, `segmentation-sweep`).

## Core rules

1. **Living docs are updated, not snapshotted.** When state changes, edit the
   ledger / status / standard. Emit a dated snapshot only if a round needs one,
   and make it cite the living doc.
2. **One front door per repo.** New indexes become sub-indexes linked from MAP.
   Never add a second competing entry point.
3. **Authority stays in the right repo.** Canon in `igniter-lang`, evidence in
   `igniter-lab`, coordination/delta in `igniter-gov`. The ledger's `do_not_infer`
   field exists to stop lab evidence reading as canon.
4. **Default reads stop at capsule Layer 2.** (Standard in
   `igniter-gov/docs/doc-segmentation-standard.md`.) Archaeology must be requested
   by a card, never accidental.
5. **Sweeps preserve history.** Move, don't rewrite. Stale claim → fresh crest
   note, original untouched.

## New anti-pattern

- Writing a fresh dated `*-delta-report.md` / `*-status.md` / `*-map.md` instead
  of updating the living document. This is the root cause of "agents become
  archaeologists": N snapshots of the same truth with no single current one.

## See also

- `igniter-gov/MAP.md` — master cross-repo map
- `igniter-gov/DELTA-LEDGER.md` — the live delta ledger + its field schema
- `igniter-gov/docs/doc-segmentation-standard.md` — fate ladder + capsule layers
