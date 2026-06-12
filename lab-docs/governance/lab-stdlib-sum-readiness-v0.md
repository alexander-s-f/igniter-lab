# Lab: stdlib.collection.sum Readiness

**Card:** LAB-STDLIB-SUM-P1  
**Date:** 2026-06-12  
**Track:** stdlib / collection / numeric  
**Route:** READINESS PROOF / NO IMPLEMENTATION  
**Proof:** `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_sum_p1.rb` — 46/46 PASS  
**Verdict:** SPLIT-NUMERIC

---

## Change Description

This proof determines the readiness verdict for `stdlib.collection.sum`. It maps the
two call forms in use across app fixtures, surveys the toolchain support gap, identifies
the Rust TC scale-stripping issue on the one-arg form, and produces a split verdict:
the two-arg field-projection form is ready for proposal; the one-arg bare form is blocked
by spec absence and numeric type stabilization.

---

## Background

LAB-STDLIB-COLLECTION-P1 (SPLIT verdict, 64/64 PASS) separated `sum` from `map`/`filter`/`count`
because it crosses collection semantics and numeric semantics. Bookkeeping uses sum for ledger
posting aggregation. The conformance fixture `stdlib_extension.ig` exercises a field-projection
sum form. The existing Rust TC dispatch for `sum` (line 2667) is partial: the two-arg form
correctly extracts the field type; the one-arg form silently returns bare `Decimal`, stripping
the scale from `Decimal[N]` inputs.

---

## Required Inputs Read

- `LAB-STDLIB-COLLECTION-P1` — collection SPLIT verdict; sum separated as Group C
- `LAB-STDLIB-FOLD-P1` — fold ACCEPT verdict (LAB-STDLIB-FOLD-P1 CLOSED)
- `LAB-STDLIB-FOUNDATION-P1` — sum in Ch8 kernel
- `LANG-STDLIB-ENTRY-CONTRACT-P3` — inventory schema and production entry pattern
- `igniter-lab/igniter-apps/bookkeeping/ledger.ig` + `types.ig` — bookkeeping sum pressure
- `igniter-lang/source/stdlib_extension.ig` — two-arg sum conformance fixture
- `igniter-lab/igniter-stdlib/stdlib/collections.ig` — stdlib spec for sum
- `igniter-lang/lib/igniter_lang/typechecker.rb` — Ruby TC dispatch (absent)
- `igniter-lab/igniter-compiler/src/typechecker.rs` — Rust TC sum dispatch (line 2667)
- `igniter-lab/lab-docs/governance/igniter-stdlib-numeric-coverage-proposal-readiness-v0.md`

---

## Call Form Survey

Two distinct call forms are in use across app fixtures:

| Form | Signature | App | Source |
|------|-----------|-----|--------|
| Two-arg | `sum(Collection[T], Symbol) -> DeclaredFieldType` | stdlib_extension | `sum(leads, :bid_decimal)`, `sum(filter(leads, ...), :bid_decimal)` |
| One-arg | `sum(Collection[Numeric]) -> Numeric` | bookkeeping ledger | `sum(debit_amounts)`, `sum(credit_amounts)` |

`debit_amounts` and `credit_amounts` in `ledger.ig` are `Collection[Decimal[2]]` — the result
of `map(postings, p -> p.amount)` where `Posting.amount: Decimal[2]`. Neither call form
involves `Collection[Integer]`.

---

## Questions Answered

**Q1. Where does `sum` appear in app fixtures?**
- `ledger.ig` lines 9, 13: `sum(debit_amounts)` and `sum(credit_amounts)` — one-arg form on
  `Collection[Decimal[2]]`
- `stdlib_extension.ig` lines 26, 28, 31, 34, 37: `sum(leads, :bid_decimal)` and
  `sum(filter(leads, ...), :bid_decimal)` — two-arg form with `:bid_decimal: Decimal[2]`
- No app fixture uses sum on `Collection[Integer]` directly

**Q2. Is `sum` currently supported in Rust?**
Yes — dispatch at `typechecker.rs` line 2667–2685:
- **One-arg form**: returns bare `Decimal` (default, scale-free) — scale-stripping gap
- **Two-arg form**: extracts field name from Symbol arg, looks up field type in `type_shapes`,
  returns declared field type (e.g., `Decimal[2]` for `:bid_decimal`)
- SIR fn name: bare `"sum"` (not qualified as `stdlib.collection.sum`) — separate parity gap

**Q3. Is `sum` currently supported in Ruby?**
No. All sum calls fall through to `infer_call`'s else branch → `OOF-TY0: Unknown function: sum`.
Confirmed for both forms: `sum(Collection[Integer])`, `sum(Collection[Decimal[2]])`,
`sum(Collection[Lead], :bid_decimal)`.

**Q4. Does `sum(Collection[Integer]) -> Integer` work?**
- Rust: the one-arg form returns bare `Decimal` by default — returns `Decimal` for
  `sum(Collection[Integer])` (wrong type). The two-arg form `sum(coll, :quantity)` where
  `quantity: Integer` returns `Integer` correctly.
- Ruby: OOF-TY0 for any sum call.
- No app fixture requires `sum(Collection[Integer])` — Integer-only acceptance is ungrounded.

**Q5. Does `sum(Collection[Float]) -> Float` work?**
Float is not a canonical type in Igniter (the numeric coverage doc confirms Float arithmetic
is rejected by both toolchains). Not applicable.

**Q6. Does `sum(Collection[Decimal[N]]) -> Decimal[N]` work or fail?**
- **Rust one-arg form**: returns bare `Decimal`, NOT `Decimal[N]` — scale is stripped.
  `sum(Collection[Decimal[2]])` → `Decimal` (incorrect; should be `Decimal[2]`)
- **Rust two-arg form**: returns the declared field type. `sum(leads, :bid_decimal)` where
  `bid_decimal: Decimal[2]` → `Decimal[2]` (correct, scale-preserving)
- **Ruby**: OOF-TY0 for both forms

**Q7. Should `sum` be limited to Integer v0?**
No. ACCEPT-INTEGER-ONLY is ungrounded: all app fixtures use Decimal sum (Decimal[2] via
field projection or via mapping Posting.amount). An Integer-only acceptance would not satisfy
any existing fixture pressure.

**Q8. Should Decimal sum wait for `LAB-STDLIB-NUMERIC-P1`?**
Partially. The two-arg form `sum(Collection[T], Symbol) -> DeclaredFieldType` does NOT
require Decimal arithmetic to be settled at the type-checking level — it returns the declared
field type from `type_shapes`, which is already `Decimal[2]`. This form is independent of
STAB-P4-OPERATOR-PARITY for type inference purposes.

The one-arg bare form `sum(Collection[Decimal[N]]) -> Decimal[N]` requires scale propagation
rules and a numeric type constraint mechanism. These are blocked by STAB-P4/LAB-STDLIB-NUMERIC-P1.

**Q9. Is `sum` canonical or fold-derived?**
Both forms are fold-derivable:
- `sum(coll) = fold(coll, 0, (acc, x) -> acc + x)` (one-arg)
- `sum(coll, :field) = fold(coll, 0, (acc, x) -> acc + x.field)` (two-arg)

However, fold is ACCEPT (LAB-STDLIB-FOLD-P1 CLOSED) but not yet implemented in Ruby TC.
Specifying sum as fold-derived would create a dependency on fold implementation. Rust TC
treats sum as an independent dispatch arm. **Independent implementation is justified** —
sum is specified with its own entry contract and implemented without fold dependency. The
derivation relationship is noted informally.

**Q10. What happens on empty collection?**
The stdlib spec returns `Decimal[S]` (no `Option` wrapper). This implies either a
convention of returning 0 (identity element) or treating empty as a domain error. No
identity element is defined anywhere in the current spec. The bookkeeping domain invariant
(a valid transaction always has postings) makes the empty case app-structurally rare but
not type-enforced. Empty-collection semantics are deferred to the proposal card.

**Q11. Does `sum` require an identity element entry contract?**
Yes, for a non-Option return type to be safe. The two-arg form does not inherently change
this problem — sum over an empty collection of records with a Decimal[2] field would still
need to return something. Options: (a) return `Option[T]`, (b) define 0 as identity,
(c) require non-empty input (runtime error). This decision is deferred to LANG-STDLIB-SUM-PROP-P1.

**Q12. Should `sumBy` be explicitly deferred?**
Yes. The two-arg form `sum(coll, :field)` IS semantically "sum-by-field", but the
function is called `sum` in all fixtures and in the stdlib spec. There is no `sumBy` in
any canonical app fixture or spec. `sumBy` as a separate name is explicitly not adopted.

---

## Toolchain Support Matrix

| Toolchain | One-arg `sum(coll)` | Two-arg `sum(coll, :field)` |
|-----------|--------------------|-----------------------------|
| **Ruby TC** | OOF-TY0 | OOF-TY0 |
| **Rust TC** | Accepts; returns bare `Decimal` (scale stripped) | Accepts; returns declared field type (scale-preserving) |
| **Stdlib spec** | NOT defined | Defined: `sum(Collection[T], Symbol) -> Decimal[S]` |
| **App usage** | ledger.ig (one-arg on `Collection[Decimal[2]]`) | stdlib_extension.ig (two-arg `:bid_decimal: Decimal[2]`) |

---

## Rust TC Dispatch Detail

```
"sum" => {
    is_resolved = true;
    let mut resolved = type_ir("Decimal");    // default: bare Decimal (one-arg form)
    if args.len() >= 2 {
        // Two-arg form: extract field name from Symbol, look up in type_shapes
        let field_name = <from Symbol arg>;
        if let Some(param) = get_param(typed_args[0].resolved_type, 0) {
            let inner_type_name = type_name(param);
            if let Some(fields) = type_shapes.get(inner_type_name) {
                if let Some(field_ty) = fields.get(field_name) {
                    resolved = field_ty.clone();   // returns declared field type
                }
            }
        }
    }
    resolved_type = resolved;
}
```

**Scale-stripping gap (one-arg)**: For `sum(amounts)` where `amounts: Collection[Decimal[2]]`,
`args.len() == 1`, so the default bare `Decimal` is returned. Scale parameter `[2]` is lost.

**Scale-preserving (two-arg)**: For `sum(leads, :bid_decimal)` where `bid_decimal: Decimal[2]`
in `Lead`'s type shape, `fields.get("bid_decimal")` returns the declared `Decimal[2]` type
node verbatim.

**SIR name gap**: The sum dispatch does not set `annotated_expr` with a qualified name.
The emitted SIR `fn` field will be the bare source name `"sum"`, not `"stdlib.collection.sum"`.
This is a parity gap separate from the type-inference gap.

---

## Verdict: SPLIT-NUMERIC

### Split A — ACCEPTED: Two-arg `sum(Collection[T], Symbol) -> DeclaredFieldType`

**Rationale:**
- Defined in `stdlib/collections.ig` spec (two-arg form only)
- Conformance-tested in Rust TC via `stdlib_extension.ig` (scale-preserving for Decimal[2] fields)
- Return type is the declared field type from `type_shapes` — no arithmetic type inference needed
- Does NOT require STAB-P4-OPERATOR-PARITY to be resolved for type-checking purposes
- Ruby TC dispatch gap is solvable: follows the `COLLECTION_HOF_FNS` constant pattern from
  LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P2; `has_lambda: false`, arity 2
- Rust SIR name is bare `"sum"` — qualified name `"stdlib.collection.sum"` must be emitted
  by Ruby TC (matching the MAP_STDLIB_FNS / OUTCOME_STDLIB_FNS precedent)

**Blocked only by:** Ruby TC implementation (solvable) + SIR qualified name (Rust parity, separate card)

**Next route:** `LANG-STDLIB-SUM-PROP-P1`

---

### Split B — BLOCKED: One-arg `sum(Collection[T]) -> T`

**Rationale for blocking:**
1. **Absent from stdlib spec** — `stdlib/collections.ig` defines only the two-arg form
2. **Rust scale-stripping bug** — `sum(Collection[Decimal[2]])` returns bare `Decimal` in Rust
3. **Numeric constraint unsettled** — requires a mechanism to constrain T to numeric types;
   the numeric coverage doc (2026-06-10) confirms STAB-P4-OPERATOR-PARITY gates all numeric
   canon promotion
4. **Identity element unspecified** — empty collection semantics require either Option or identity
5. **No spec basis + two-toolchain gap** — cannot author an entry contract for a form that is
   absent from the spec and has a known Rust type gap

**Blocked by:** STAB-P4-OPERATOR-PARITY / LAB-STDLIB-NUMERIC-P1 + spec authoring

---

### sumBy deferral

`sumBy` is not a function in any canonical fixture or in the stdlib spec. The two-arg
`sum(coll, :field)` form is sum-by-field semantically, but it uses the `sum` name. No
`sumBy` alias is accepted. Explicitly deferred.

---

## Proof Section Summary

| Section | Checks | Focus |
|---------|--------|-------|
| A — Stdlib spec | 5 | two-arg defined; one-arg absent; sumBy absent; no inventory entry |
| B — Fixture survey | 8 | app forms confirmed; Decimal[2] element types; no Integer demand |
| C — Ruby diagnostics | 8 | OOF-TY0 both forms; no dispatch constant; no when arm |
| D — Rust dispatch | 6 | dispatch present; default Decimal; field-type extraction; no qualified name |
| E — Integer evidence | 4 | Rust accepts; Ruby rejects; ACCEPT-INTEGER-ONLY ungrounded |
| F — Decimal evidence | 4 | two-arg scale-preserving; one-arg scale-stripped; Split B justified |
| G — Empty collection | 3 | no Option wrapper; no identity; domain structural context |
| H — Fold relationship | 3 | fold ACCEPT; sum derivable; independence justified |
| I — sumBy + authority | 5 | no sumBy; authority closed; no implementation |

**Total: 46/46 PASS**

---

## Open Items

1. **Split B spec authoring**: A one-arg `sum(Collection[T]) -> T where T: Numeric` form
   needs a numeric type constraint mechanism. Currently not defined. Must wait for
   STAB-P4-OPERATOR-PARITY and a numeric constraint proposal.
2. **Empty collection semantics**: Deferred to LANG-STDLIB-SUM-PROP-P1. Decision: return 0
   (identity) or return Option[T] or require non-empty. The spec's non-Option return implies
   identity-0 convention, but this must be explicit.
3. **Rust SIR name**: Bare `"sum"` instead of `"stdlib.collection.sum"` is a Rust parity gap.
   Separate from Ruby TC proposal. Post-P1 parity card.
4. **Scale-stripping Rust bug**: One-arg `sum(Collection[Decimal[2]])` → `Decimal` in Rust.
   Fixing requires either (a) extending the one-arg dispatch to extract element type and preserve
   scale, or (b) removing one-arg support until spec is authored. Post-P1 parity card.

---

## Authority Closed

- No Ruby TypeChecker implementation
- No Rust TypeChecker implementation
- No VM/runtime changes
- No stdlib-inventory.json edits
- No app fixture changes
- No fold implementation
- No Decimal literal/operator implementation
- No sumBy name introduced
- No public API claim

---

## Next Routes

**Split A path (accepted):**
`LANG-STDLIB-SUM-PROP-P1`  
Entry contract for `stdlib.collection.sum` two-arg form. Signature: `Collection[T] × Symbol → DeclaredFieldType`. Ruby TC implementation planning. Bookkeeping and stdlib_extension as fixtures.

**Split B path (blocked):**
After `LAB-STDLIB-NUMERIC-P1` / STAB-P4-OPERATOR-PARITY resolves the numeric type constraint.

**Parity path (separate):**
Rust TC: fix scale-stripping in one-arg form + emit qualified `stdlib.collection.sum` SIR name.
