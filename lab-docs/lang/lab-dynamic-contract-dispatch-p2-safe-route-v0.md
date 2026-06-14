# LAB-DYNAMIC-CONTRACT-DISPATCH-P2: Safe Route for Dynamic Contract Dispatch

Date: 2026-06-14
Card: LAB-DYNAMIC-CONTRACT-DISPATCH-P2
Status: CLOSED — PROVED 47/47 — ROUTE SELECTED: DEFER + NO-CHANGE + PRESERVE FAIL-CLOSED
Authority: lab-only policy/proof planning — no canon claim, no stable-API surface, no implementation

---

## Summary

The safe route for `rule_engine` dynamic contract dispatch is **DEFER**:

> **DEFER** dynamic-dispatch implementation, **NO-CHANGE** to `rule_engine` source,
> and **PRESERVE** the current dual-toolchain fail-closed boundary. The single
> sanctioned forward design is a **static, compile-time-resolved typed closed
> strategy union / typed contract reference** — itself canon-gated, and **not**
> implemented or authorized by this card.

This is a *no-implementation* outcome by design. The card explicitly states the
current blocked state is "intentional fail-closed evidence, not an accidental
syntax gap," and forbids unblocking by making `Unknown` permissive or weakening
output assignability. The route therefore keeps the evidence intact rather than
spending it.

The key source form stays exactly as-is:

```igniter
compute raw_decisions = map(rules, r -> call_contract(r, t))   -- engine.ig:17-18
```

where `r : String` from `input rules : Collection[String]` (Tier 2, non-literal
callee). It resolves to `Unknown`, propagates through `filter`, and is rejected
at the typed output boundary. Both toolchains agree it is blocked.

---

## Current Baseline (ground-truthed 2026-06-14)

Compiled fresh against the live `igniter_compiler` release binary and the Ruby TC:

| Toolchain | Status | Diagnostics |
|-----------|--------|-------------|
| Rust | `oof` / 2 | `OOF-P1 Unresolved field: Unknown.action` + `OOF-TY1 Output type mismatch: expected RuleDecision, got Unknown` |
| Ruby | `oof` / 2 | `OOF-P1 Unresolved symbol: d` + `OOF-P1 Unresolved field: Unknown.action` |

This matches PRESSURE_REGISTRY Wave P9/P10 and **supersedes** the P1 runner's
frozen form (`2× OOF-TY1` in Rust). The Rust shape changed because
LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2 made `filter`/`map` lambda-body errors
propagate (so `d.action` now raises OOF-P1 in Rust too, suppressing the
collection-level OOF-TY1 via `blocking_rule_present?`). The element-level
OOF-TY1 survives. The safety outcome is unchanged: **no Unknown-to-concrete path
compiles.**

`rule_engine` is the only blocked app in the 13-app fleet; `trade_robot` is
dual-clean and avoids dynamic strategy dispatch (TR-P06).

---

## The Seven Questions

### Q1. Should variable callees remain compile-time blocked unless a typed registry is declared?

**Yes.** A Tier 2 (variable / non-literal) callee resolves to `Unknown` because
the compiler cannot statically resolve the target contract name, and therefore
cannot know the result type. With a concrete typed output annotation, `Unknown`
is rejected at the boundary by decision rule D2 (`actual == Unknown → false`,
LANG-OUTPUT-TYPE-ASSIGNABILITY-P4). This block is load-bearing and must remain.

The block lifts only when a **statically-known result type** is available — i.e.
when the callee is drawn from a **declared, closed, typed set** (a typed contract
reference or a closed strategy union, see Q2/Q3) rather than an open runtime
string. An open `Collection[String]` of names is *not* such a registry and stays
blocked.

### Q2. Is a declared strategy union sufficient for `rule_engine` and `trade_robot`-style pressure?

**Sufficient in principle, but only as a closed declared set — and the feature
does not exist in canon yet.**

A declared union `uses strategy : A | B | C` where every member shares a common
output type `T` makes the dispatch result type statically equal to the join of
the members (`T`, or the union itself). No `Unknown` is introduced.

- `trade_robot`: all strategies (`SMACrossoverStrategy`, `RSIMeanReversion`,
  `CombinedStrategy`) output `Signal`. A union over them yields `Signal`
  statically — sufficient. The app already approximates this by hardcoding
  `CombinedStrategy` in `StrategyDispatcher` (a degenerate one-member union).
- `rule_engine`: rules follow the informal `Transaction -> RuleDecision` shape
  (RE-P05). A union of rule contracts all returning `RuleDecision` would yield
  `Collection[RuleDecision]` statically — sufficient.

The decisive safety property: the union must be **closed and declared at compile
time**. The current `rule_engine` form is an **open, runtime-populated**
`Collection[String]` — the antithesis of a closed union — so it is *not*
covered. A declared union is a different program, not a reinterpretation of the
existing one. The feature (union-over-contracts + a join/assignability rule) is
not in the canon language surface; it is a forward design target, not an
available route.

### Q3. What would a typed plugin registry look like without runtime reflection authority?

A **compile-time** registry, not a runtime lookup table:

- A declared, finite mapping whose keys are **enum tags / contract references**,
  not arbitrary runtime strings.
- Each member is a typed contract reference `Contract[In -> Out]` with a checked
  signature.
- Dispatch resolves against the declared set **at typecheck time**; the
  "selector" is a tag the compiler can enumerate, so there is no name→contract
  resolution that can fail open at runtime.
- The result type is the join of member output types — statically known.
- The set is finite and statically checkable; adding a member is a source edit
  the typechecker re-verifies.

This is **typed contract references + a closed union**, *not* a
`String → Contract` hashmap resolved by the VM. The distinction is exactly the
no-reflection boundary: enumeration at compile time vs. lookup at runtime. The
former never produces `Unknown` and never fails open; the latter is precisely
the stringly authority that stays closed.

### Q4. Can validation receipts narrow `Unknown` to `RuleDecision` safely, or is that runtime authority creep?

**As a bare narrowing, it is authority creep and is rejected.** A receipt that
licenses compile-time `Unknown` to flow into a concrete typed output on the
strength of a runtime check re-introduces upward coercion — the exact thing
D2/OOF-TY1 closes — gated on an artifact the typechecker cannot verify. That is
"runtime stringly authority" by another name.

A receipt can participate in a *safe* future design **only** if:

1. The narrowing target is a **typed `Result[T]` / option**, never a bare `T` —
   i.e. `Unknown → Result[RuleDecision]`, a total, fail-closed combinator.
2. The output boundary still sees a typed `Result[T]`; the success branch is
   reached only after an explicit, checked match. No path lets an unverified
   `Unknown` reach a `RuleDecision` slot.

So: receipts are admissible only as explicit, fail-closed, typed validation
combinators — never as a silent cast. Designing those is out of scope here and
requires canon authority (it touches the type system's narrowing rules).

### Q5. Is `output : Unknown` quarantine acceptable only for lab demos, and how should it be labeled?

**Acceptable only as an explicitly-labeled lab quarantine, and — importantly —
it is not even a clean route for `rule_engine`.**

Declaring `output foo : Unknown` invokes the D3 escape hatch (`expected Unknown
→ true`) and removes the boundary OOF-TY1. But per LAB-UNKNOWN-FIELD-ACCESS-P1,
Ruby still fires `OOF-P1` for `d.action` field access inside the HOF lambda. The
proof confirms it (D-07): the field-access pipeline does not compile clean even
with `output : Unknown`. So the quarantine grants no capability and does not
rescue the `rule_engine` shape.

Where used at all (only in isolated lab snippets, never in fleet apps), it must
be labeled inline and in the registry, e.g.:

```igniter
-- QUARANTINE [LAB-ONLY]: output:Unknown — no type safety at boundary; grants no
-- capability; not a clean compile for field-access pipelines. See
-- LAB-DYNAMIC-CONTRACT-DISPATCH-P2 §Q5.
output foo : Unknown
```

`rule_engine` keeps its concrete `Collection[RuleDecision]` annotation precisely
so it remains honest fail-closed evidence rather than a silenced quarantine.

### Q6. What exact proof would be required before any dynamic-dispatch implementation card?

A future implementation card must prove, **dual-toolchain**, all of:

1. **Static resolution** — the declared typed union / contract-reference dispatch
   resolves the result to a concrete `T` (or closed union) at typecheck time; no
   `Unknown` is introduced.
2. **Member agreement** — members are verified to share the declared output type;
   a mismatched member raises an OOF (no silent widening).
3. **Open-string regression guard** — open `Collection[String]` dispatch still
   resolves to `Unknown` and still fails closed at a typed boundary (D2 intact).
4. **Field-access safety** — field access on the dispatch result is checked
   against the union's common type, never permissive `Unknown` (OOF-P1 preserved
   for the Unknown path).
5. **No reflection** — the dispatch set is enumerable at compile time; there is
   no `String → Contract` runtime lookup that can fail open.
6. **Fail-closed primitives** — unknown tag / arity / purity violations raise
   OOF-TY0 (as Tier 1 literal dispatch already does — proven F-03/F-04).
7. **Boundary preservation** — OOF-TY1 / D2 output assignability and
   LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 are not regressed.
8. **Canon authority first** — a Covenant / spec amendment declaring the union /
   contract-reference surface must land *before* implementation. Lab cannot
   self-authorize a language feature.

### Q7. What stays closed: duck typing, field access on Unknown, typed-output coercion, runtime stringly authority?

All four stay closed; the proof asserts each (Section G):

| Surface | Status | Mechanism |
|---------|--------|-----------|
| Duck typing (structural access granting capability) | **CLOSED** | field access on `Unknown` is an error, not a capability |
| Field access on `Unknown` | **CLOSED** | OOF-P1 in both TCs (`Unresolved field: Unknown.X`) |
| Typed-output coercion (`Unknown → T`) | **CLOSED** | OOF-TY1 / D2 (LANG-OUTPUT-TYPE-ASSIGNABILITY-P4) |
| Runtime stringly authority (`String → Contract` at runtime) | **CLOSED** | no implementation, no reflection, no VM dispatch surface |

---

## Safety Classification (carried forward from P1, re-confirmed)

| Form | Example | Status | Gate |
|------|---------|--------|------|
| Literal / static closed-set callee | `call_contract("RuleA", x)` | ACCEPTED | resolves to concrete type; OOF-TY0 fail-closed |
| Dynamic callee, `Unknown` output | `call_contract(name) → Unknown` | QUARANTINED | `output : Unknown`; no capability; not clean for field access |
| Dynamic callee, typed output | `call_contract(name) → Collection[T]` | BLOCKED | OOF-TY1 at boundary (D2) |
| Field access on `Unknown` | `d.action` where `d : Unknown` | CLOSED | OOF-P1 both TCs |

---

## Route Decision

**ROUTE = DEFER (implementation) + NO-CHANGE (rule_engine source) + PRESERVE fail-closed.**

Rationale against the four allowed outcomes (implement / defer / quarantine / no-change):

- **Not implement** — the only safe forward design (closed typed union / typed
  contract reference) is an unimplemented, canon-gated language feature. Lab has
  no authority to add it, and Q6's proof obligations are unmet.
- **Not quarantine** (for `rule_engine`) — `output : Unknown` does not produce a
  clean compile for the field-access pipeline (Q5 / D-07) and would convert
  honest fail-closed evidence into a silenced demo. Quarantine remains a
  *documented, labeled* lab-only escape hatch, not a route for this app.
- **No-change for the apps** — `rule_engine` stays as fail-closed evidence;
  `trade_robot` already carries the positive static-dispatch baseline (TR-P06,
  dual-clean). Neither needs a source edit, and the card forbids migrating
  `rule_engine` unless the doc explicitly selects source-level static dispatch —
  which it deliberately does **not**, to keep the evidence.
- **Defer the feature** — the forward design is named and its proof bar is set
  (Q6), but routed to a future canon-gated card, not opened here.

This preserves LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 and OOF-P1 field-access safety,
accounts for `trade_robot` avoiding dynamic dispatch, and does not mark
`rule_engine` resolved.

---

## Proof

```
proof runner:  igniter-lab/igniter-apps/rule_engine/verify_dynamic_dispatch_p2.rb
checks:        47/47 PASS
sections:      A preconditions (6) / B Rust current form (7) / C Ruby current form (5) /
               D Tier 2 classification (7) / E trade_robot static baseline (6) /
               F static typed-dispatch proxy (5) / G closed surfaces (6) /
               H route decision (5)
```

---

## Closed Surfaces (this card)

- No permissive `Unknown.action`.
- No `Collection[Unknown] → Collection[T]` output coercion.
- No stringly runtime authority.
- No VM / runtime reflection implementation.
- No app source migration (no `rule_engine` source-level dispatch rewrite).
- No new OOF codes.
- No compiler / TC source changes.

---

## Open Routes (successors)

| Card | Scope |
|------|-------|
| (future, canon-gated) Typed closed strategy union / typed contract reference | Implementation, only after a Covenant/spec amendment and Q6's 8-part proof |
| LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2 | Parametric container assignability implementation planning |
| LAB-HOF-LAMBDA-ERROR-PROPAGATION-P3 | flat_map parity (deferred — Integer placeholder params) |
