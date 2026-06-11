# LAB-STDLIB-FOUNDATION-P1 — Stdlib Surface Inventory and Entry Contract

**Track:** stdlib-surface-inventory-and-entry-contract-v0
**Route:** RESEARCH / DESIGN BOUNDARY / NO IMPLEMENTATION
**Status:** CLOSED — SPLIT
**Date:** 2026-06-11

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Research doc | `igniter-lab/lab-docs/governance/lab-stdlib-surface-inventory-and-entry-contract-v0.md` | Written |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-STDLIB-FOUNDATION-P1.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Headline Findings

1. **Only one reference-quality category exists.** `stdlib.text` (14 ops) has
   full three-way agreement: Ch8 canon + Ruby production registry + Rust VM
   dispatch. `stdlib.map` (4 ops, PROP-043) is close behind. Everything else is
   partial on at least one axis.

2. **Executable-truth inversion (D5).** The only fully executable stdlib is the
   lab Rust VM (explicitly non-canonical per its README); canon's kernel-proven
   collection surface (fold/map/filter/sum/avg/min/max/group_by/sort_by/take/
   first/last) largely does not run anywhere ("pending Slice A"). Current
   stability language conflates "accepted" with "executable".

3. **SIR namespace drift found (D1).** Every stdlib call lowers to a qualified
   name (`stdlib.text.concat`, `stdlib.map.get`) EXCEPT `or_else` — deliberately
   emitted bare ("no stdlib. prefix — v0 design", typechecker.rb:2092). Two
   namespace regimes in one SIR.

4. **Option constructor drift found (D2).** Canon Ch8 defines `some`/`none`; the
   only executable Option constructor is VM-only `stdlib.option.wrap` — a name
   canon never defined. Also orphaned: `stdlib.bool.and`, `stdlib.integer.gt`,
   `stdlib.collection.concat` (single-surface names with `stdlib.` prefix).

5. **Temporal names are disjoint sets (D3).** Ch8 §8.6 (`add_duration, diff,
   as_of`) vs proven `datetime_extension.ig` (`diff_seconds, add_seconds,
   parse_datetime, format_datetime, is_before, is_after`) — zero overlap; no
   artifact says which is canonical.

6. **Numeric category HOLD confirmed (D4).** Ch8 §8.5 lists `stdlib.float.add`
   (rejected by BOTH typecheckers) and `stdlib.decimal.*` (Rust-yes/Ruby-no).
   STAB-P4 operator parity gates the entire numeric/math category; demand is
   proven (LAB-PURSUIT N0/N1: abs/min/max/clamp/compare/sign + isqrt/ipow/
   imuldiv) but inclusion before parity bakes divergence in.

7. **False stdlib partitioned** into four classes: proof-local helpers
   (LAB-PURSUIT fixed-point machinery — demand evidence, not entries),
   domain-local helpers (query/storage/outcome ad-hoc records), orphaned names
   (finding 4), doc-sketch declarations (`igniter-stdlib/stdlib/*.ig` uses
   non-canon `def` syntax + `stdlib.Math` capitalization — design sketches in a
   stdlib costume, zero surface authority).

8. **Entry contract schema concretized** (extends RES-001 §3.1): canonical_name
   (qualified lowercase, the identity), source_name, aliases (churn ledger —
   renames recorded never erased), category, fragment_class, purity, signature,
   deterministic, totality, failure_behavior, diagnostics, authority_surface
   (capability-param-only; grant fields schema-absent — same rule as packages),
   lowering (per-toolchain + kernel_only flag), stability (orthogonal to
   executability), proof, lineage, since. Sorted canonical-JSON inventory hash =
   `stdlib_surface_digest` (PROP-036 pattern) — also exactly the object the
   package research needs for "stdlib = the package the compiler vouches for".

9. **Inclusion criteria:** cross-domain demand (≥2 independent proof domains),
   tier-decidable, total-or-honestly-partial, deterministic-or-capability-gated,
   signature expressible today (else `reserved`), proof coverage per stability
   bar, no hidden authority / no domain-local leakage.

10. **Biggest blind spot = outcome/KDR combinators** (RES-001 Q3 + epistemic-
    outcome lineage): canon defines the unknown-state model, stdlib offers zero
    combinators, proofs flatten epistemic outcomes into ad-hoc `kind:` records.
    Shippable convention-level pre-sum-types (`is_unknown`,
    `requires_reconciliation`, `partition_partial`), module marked
    superseded-by-variants.

---

## Category Verdicts

text READY (reference) · map READY · option/result READY-for-reconciliation ·
collection SPLIT (count production / §8.2 reserved / examples triage) ·
numeric HOLD (D4) · datetime HOLD (D3) · outcome OPEN-as-convention ·
query DOMAIN-LOCAL · io/net/storage L3-reserved · bool DO-NOT-CREATE.

---

## Verdict

**CLOSED — SPLIT:**

1. **LANG-STDLIB-ENTRY-CONTRACT-P1** — entry-contract schema + reconciled
   inventory proposal; resolves D1/D2/D5; defines `stdlib_surface_digest`.
   Ready now.
2. **LAB-STDLIB-OUTCOME-P1** — convention-level KDR combinators proof.
3. **LAB-STDLIB-OPTION-P1** — Option/Result executable-parity reconciliation
   (after entry-contract P1).
4. **LAB-STDLIB-COLLECTION-P1** — example-name triage + honest reserved marking
   (after entry-contract P1).
5. **LAB-STDLIB-MATH-P1** — N0/N1 records as `reserved`; gated on D4/STAB-P4.
6. **LAB-STDLIB-DATETIME-P1** — D3 per-name triage (after entry-contract P1).

---

## Closed Surfaces (unchanged)

Stdlib implementation / parser/typechecker changes / VM changes /
package-distribution design / registry/versioning / public compatibility promise.
