# LAB-STDLIB-SUM-P1 — stdlib.collection.sum Readiness Proof

**Track:** stdlib / collection / numeric  
**Route:** READINESS PROOF / NO IMPLEMENTATION  
**Status:** CLOSED — SPLIT-NUMERIC / LANG-STDLIB-SUM-PROP-P1 UNBLOCKED (two-arg form)  
**Date:** 2026-06-12  
**Predecessors:** LAB-STDLIB-COLLECTION-P1 (64/64 PASS, SPLIT), LAB-STDLIB-FOLD-P1 (ACCEPT), LANG-STDLIB-ENTRY-CONTRACT-P3

---

## Goal

Determine whether `sum` should be a canonical stdlib helper, a fold-derived form, or deferred
behind numeric type stabilization.

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Lab doc | `igniter-lab/lab-docs/governance/lab-stdlib-sum-readiness-v0.md` | Written |
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_sum_p1.rb` | Written — 46/46 PASS |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-STDLIB-SUM-P1.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Verdict: SPLIT-NUMERIC

### Split A — ACCEPTED: Two-arg form `sum(Collection[T], Symbol) -> DeclaredFieldType`

The field-projection form is ready for proposal authoring.

**Evidence:**
- `stdlib/collections.ig` defines ONLY the two-arg form: `sum(coll: Collection[T], field: Symbol) -> Decimal[S]`
- Conformance-tested in Rust TC via `stdlib_extension.ig` (`sum(leads, :bid_decimal)` where `bid_decimal: Decimal[2]` → returns `Decimal[2]`)
- Rust TC dispatch (line 2667): extracts field type from `type_shapes` — scale-preserving for declared Decimal[N] fields
- Return type is the declared field type — does NOT require arithmetic type inference or numeric constraint resolution
- Ruby TC dispatch gap is solvable (follows the `COLLECTION_HOF_FNS` pattern from PROP-P2; `has_lambda: false`, arity 2)
- `semantic_ir_name == canonical_name` invariant: Ruby TC will emit `"fn" => "stdlib.collection.sum"` (qualified), following MAP/OUTCOME precedent

**Blocked only by:** Ruby TC implementation (solvable, no new primitives needed)

**Next route:** `LANG-STDLIB-SUM-PROP-P1`

---

### Split B — BLOCKED: One-arg form `sum(Collection[T]) -> T`

The bare element-sum form cannot proceed.

**Blocking conditions:**
1. Absent from `stdlib/collections.ig` spec — no canonical signature
2. Rust TC scale-stripping bug: `sum(Collection[Decimal[2]])` returns bare `Decimal` (not `Decimal[2]`)
3. Requires numeric type constraint mechanism (T: Numeric) — not defined
4. Requires scale propagation rule for sum of Decimal[N]
5. Identity element (sum over empty collection) unspecified
6. Blocked by STAB-P4-OPERATOR-PARITY / LAB-STDLIB-NUMERIC-P1

---

## Call Form Survey

| Form | Apps | Operand type |
|------|------|-------------|
| `sum(debit_amounts)` — one-arg | ledger.ig lines 9, 13 | `Collection[Decimal[2]]` |
| `sum(leads, :bid_decimal)` — two-arg | stdlib_extension.ig lines 26–37 | `Collection[Lead]`, field `Decimal[2]` |

No app uses `sum(Collection[Integer])` — **ACCEPT-INTEGER-ONLY is ungrounded**.

---

## Toolchain Status

| | Ruby TC | Rust TC |
|-|---------|---------|
| One-arg `sum(coll)` | OOF-TY0 | Accepts; returns bare `Decimal` (scale stripped) |
| Two-arg `sum(coll, :field)` | OOF-TY0 | Accepts; returns declared field type (scale-preserving) |
| SIR fn name | — | Bare `"sum"` (not qualified) — parity gap |

---

## fold Relationship

Both forms are fold-derivable:
- `sum(coll) = fold(coll, 0, (acc, x) -> acc + x)`
- `sum(coll, :field) = fold(coll, 0, (acc, x) -> acc + x.field)`

LAB-STDLIB-FOLD-P1 is ACCEPT. However, fold is not yet implemented in Ruby TC.
Independent sum implementation is justified — avoids a fold dependency for a simpler operation.
Rust TC treats sum and fold as independent dispatch arms (confirmed by source inspection).

---

## sumBy Deferral

No app fixture uses `sumBy`. The two-arg `sum(coll, :field)` form is semantically
sum-by-field but uses the `sum` name in all fixtures and in the stdlib spec. No `sumBy`
alias is introduced.

---

## Authority Closed

No Ruby TC implementation / No Rust implementation / No VM changes /
No stdlib-inventory.json edits / No app fixture changes / No fold implementation /
No Decimal/operator implementation / No sumBy name / No public API claim.

---

## Next Routes

1. **LANG-STDLIB-SUM-PROP-P1** — entry contract + Ruby TC proposal for two-arg form (Split A path)
2. **LAB-STDLIB-NUMERIC-P1** — numeric type constraint resolution (gates Split B)
3. Post-Split-A: Rust parity card — fix scale-stripping in one-arg form + qualified SIR name
