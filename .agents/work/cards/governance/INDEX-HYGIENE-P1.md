# INDEX-HYGIENE-P1 - Portfolio / Proposal Index Hygiene

**Track:** governance / hygiene
**Route:** INDEX REPAIR ONLY / NO IMPLEMENTATION
**Status:** CLOSED - COMPLETED
**Date:** 2026-06-12

---

## Goal

Prevent accidental commit of a corrupted or misleading index after concurrent agent updates.

---

## Findings

- `igniter-lab/.agents/portfolio-index.md` was short, but `HEAD` was already a compact 6-line portfolio index. This is not evidence that a large historic index must be restored in this slice.
- Current working copy had valid fresh entries, but order was inconsistent after concurrent writes.
- `igniter-lang/.agents/work/proposals/README.md` was not truncated: 315 lines, with the current stdlib/import/append/text/is-empty rows present.
- `igniter-apps/neural_net/PRESSURE_REGISTRY.md` and `igniter-apps/rule_engine/PRESSURE_REGISTRY.md` were untracked and should be included in the next commit scope.

---

## Actions

- Rebuilt `igniter-lab/.agents/portfolio-index.md` in compact newest-first order.
- Preserved the current compact-format convention instead of resurrecting an old large index.
- Added this card so the hygiene repair is traceable.
- No source implementation files changed by this hygiene card.

---

## Checks

- `wc -l` on `igniter-lang/.agents/work/proposals/README.md`: 315 lines.
- `rg` check confirmed current stdlib proposal rows are present.
- Final `git diff --check` should be run before commit across both repos.

---

## Next

Proceed to commit after staging the intended app pressure registries and current proof artifacts.
