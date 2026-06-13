# LAB-UNKNOWN-FIELD-ACCESS-P1: Unknown Field Access Safety Boundary

Date: 2026-06-13
Card: LAB-UNKNOWN-FIELD-ACCESS-P1
Status: CLOSED — PROVED 35/35 — SAFETY POLICY ESTABLISHED
Authority: lab-only — no canon claim, no compiler changes, no implementation

---

## Context

LAB-DYNAMIC-CONTRACT-DISPATCH-P1 classified `call_contract(variable, args)` + typed output
as BLOCKED (OOF-TY1) and deferred field access on the Unknown result to this card.
The specific pressure: `rule_engine/engine.ig:27` — `d.action` inside a `filter` lambda
where `d : Unknown` (element of `Collection[Unknown]` from Tier 2 dynamic dispatch).

This card answers the seven core questions and closes with a policy table.

---

## Q1. Where does field access on Unknown occur in apps?

**One site: `rule_engine/engine.ig:27`**

```igniter
compute active_decisions = filter(raw_decisions, d ->
  if d.action == "SKIP" { false } else { true }
)
```

`d` is the lambda parameter bound to the element type of `raw_decisions`.
Since `raw_decisions : Collection[Unknown]` (produced by Tier 2 dynamic dispatch in
`map(rules, r -> call_contract(r, t))`), the element type is `Unknown`, and `d : Unknown`.
Consequently `d.action` is field access on an Unknown-typed object.

**All other apps in the fleet**: field access only on objects whose types resolve to known
record shapes (e.g. `Transaction`, `Layer`, `Document`). No Unknown field access in any
other app.

---

## Q2. Does Ruby allow it, block it, or degrade it?

**Ruby BLOCKS Unknown field access — OOF-P1 fires in all contexts.**

Mechanism (`typechecker.rb:963-975`):
```ruby
object = infer_expr(expr.fetch("object"), ...)
object_type = type_name(object.fetch("resolved_type"))      # → "Unknown"
field_type = @type_shapes.fetch(object_type, {})[field]
             || type_ir("Unknown")                          # → Unknown (not in type_shapes)
if type_name(field_type) == "Unknown"
  type_errors << oof("OOF-P1",
    "Unresolved field: #{object_type}.#{field}", ...)       # fires
end
```

Additionally, in a HOF lambda context, the lambda parameter bound to `Unknown` also
fires `OOF-P1 "Unresolved symbol: {param}"` (typechecker.rb:929):
```ruby
type_errors << oof("OOF-P1", "Unresolved symbol: #{name}", ...) if type_name(type) == "Unknown"
```

Ruby HOF `filter`/`map` passes the **same `type_errors` reference** into the lambda
body typecheck (`infer_lambda_body`, typechecker.rb:2544). So lambda body OOF-P1 errors
propagate to the parent contract's error list.

**Ruby rule_engine diagnostics (Wave P7)**:
- `Unresolved symbol: d` — lambda parameter typed Unknown
- `Unresolved field: Unknown.action` — field access on Unknown object

---

## Q3. Does Rust allow it, block it, or degrade it?

**Rust BLOCKS Unknown field access in direct context. In HOF lambda context, Rust
SILENCES lambda body errors — a documented divergence.**

**Direct context** (typechecker.rs:2414-2425):
```rust
let field_type = type_shapes.get(&obj_type)
    .and_then(|fields| fields.get(field))
    .cloned()
    .unwrap_or_else(|| self.type_ir(Unknown));  // obj_type == "Unknown" → field_type = Unknown

if self.type_name(&field_type) == "Unknown" {
    type_errors.push(OOF-P1 { "Unresolved field: {obj_type}.{field}" });
}
```

This is symmetric with Ruby — OOF-P1 fires in direct context.

**HOF lambda context** — the divergence (typechecker.rs:2975-3024 for `filter`,
typechecker.rs:3062-3103 for `map`):
```rust
let mut temp_errors = Vec::new();       // ← separate error buffer
let body_type = match body {
    Expr(...) => self.infer_expr(e, &local_symbols, ..., &mut temp_errors, ...)
};
// temp_errors is NEVER merged into type_errors — discarded after use
```

Only the OOF-COL3 check (predicate must return Bool) propagates from the lambda body.
All other errors — including OOF-P1 for field access on Unknown — are silenced.

**Rust rule_engine diagnostics (Wave P7)**:
- `Output type mismatch: expected Collection[RuleDecision], got Collection[Unknown]` (OOF-TY1)
- `Output type mismatch: expected RuleDecision, got Unknown` (OOF-TY1)
- **Zero OOF-P1** for `d.action` — silenced by temp_errors in HOF lambda

---

## Q4. Does Unknown field access bypass output safety?

**No — output safety is not bypassed. The diagnostic path differs by toolchain.**

**Ruby**: OOF-P1 fires first (for `d` and `d.action`). The `blocking_rule_present?("OOF-P1")`
guard suppresses OOF-TY1 at the output boundary. The contract does not compile clean —
OOF-P1 is the authoritative signal. Output safety enforced via upstream OOF-P1.

**Rust**: HOF lambda OOF-P1 is silenced. But the output boundary check (`structurally_assignable?`)
still fires OOF-TY1 for `Collection[Unknown] → Collection[RuleDecision]` (D2 rule). Output
safety enforced via OOF-TY1 at the boundary.

**Invariant**: in both toolchains, the Unknown field access + typed output path does not
compile clean. Ruby blocks via OOF-P1 upstream; Rust blocks via OOF-TY1 at the boundary.

---

## Q5. Should it require explicit quarantine via output Unknown?

**Partially.** Declaring `output : Unknown` removes the OOF-TY1 boundary check (D3 rule
permits any actual type when expected is Unknown). However, OOF-P1 for the field access
itself continues to fire in Ruby (and in Rust for direct non-HOF field access). There is
no current mechanism to suppress OOF-P1 for field access on Unknown.

A complete escape hatch for the rule_engine pattern would require:
1. `output active_decisions : Unknown` → removes OOF-TY1 at output boundary
2. Ruby still fires OOF-P1 inside the lambda body (Rust silences in HOF context)

**Verdict**: `output : Unknown` is a partial quarantine — removes the output boundary
block, but does not clear all diagnostics. The full quarantine path is not available
without additional toolchain work.

---

## Q6. Should it produce OOF-P1, OOF-TY0, or a new code?

**OOF-P1 is the correct code. No new code is needed.**

`OOF-P1 "Unresolved field: Unknown.{field}"` is semantically accurate: when the object's
type is Unknown, the field is genuinely unresolved. The code already distinguishes between
field-not-found (OOF-P1) and type-mismatch (OOF-TY0 / OOF-TY1).

The HOF lambda divergence (Rust silencing OOF-P1 in `temp_errors`) is not a semantic
decision about field access — it is an implementation characteristic of the HOF lambda
body typecheck isolation. This divergence should be documented, not papered over with
a new diagnostic code.

A separate card (LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1) could address the Rust HOF lambda
silencing behaviour. That is out of scope here.

---

## Q7. What route would unblock rule_engine safely?

**No safe unblock route exists in the current stage.** The full problem is:

1. `call_contract(r, t)` → Unknown (Tier 2 — no static type) — RE-P02
2. `map(rules, r -> ...)` → Collection[Unknown] — RE-P02
3. `filter(raw_decisions, d -> d.action == "SKIP")` — OOF-P1 in Ruby for `d` and `d.action`
4. `output active_decisions : Collection[RuleDecision]` — OOF-TY1 in Rust (D2 rule)

A safe unblock requires resolving the root: Tier 2 dispatch must return a known type.
That requires one of:

- **Validation receipt** (described in LANG-OUTPUT-TYPE-ASSIGNABILITY-P1 as future work):
  the callee signature verified at dispatch time via a receipt mechanism. Not scoped.
- **Tier 2 type narrowing**: explicit type annotation or cast for the dynamic dispatch
  result. No cast operator exists in the language surface. Not scoped.
- **Static rule-set model**: convert `rules : Collection[String]` to a typed dispatch
  table where each entry has a known output type. Architectural change, out of scope.

**Interim (non-blocking) option**: declare `output active_decisions : Unknown`. This
removes OOF-TY1 but: (a) loses all output type safety, (b) Ruby still fires OOF-P1
for `d` and `d.action` inside the HOF lambda body. The app remains non-clean in Ruby.

**Recommendation**: leave rule_engine blocked as documented evidence of the Unknown
propagation hazard. Do not change the source.

---

## Toolchain Divergence Summary

| Context | Ruby | Rust | Status |
|---------|------|------|--------|
| Direct `r.field` where `r : Unknown` | OOF-P1 fires | OOF-P1 fires | Parity |
| HOF lambda `d.field` where `d : Unknown` | OOF-P1 fires (propagates) | OOF-P1 silenced (`temp_errors`) | **Diverged** |
| Output boundary Unknown→T | OOF-P1 upstream suppresses OOF-TY1 | OOF-TY1 fires (D2 rule) | Different path, same safety outcome |

---

## Safety Policy Table

| Form | Status | Evidence |
|------|--------|---------|
| Field access on concrete record type | ACCEPTED | All non-dynamic apps clean |
| Direct field access on Unknown (`r.field`, `r : Unknown`) | BLOCKED | OOF-P1 (both TCs) |
| HOF lambda field access on Unknown (Ruby) | BLOCKED | OOF-P1 propagates from lambda body |
| HOF lambda field access on Unknown (Rust) | SILENCED in lambda; BLOCKED at output | temp_errors in HOF; OOF-TY1 at boundary |
| Unknown field access + Unknown output | PARTIAL QUARANTINE | Removes OOF-TY1 but OOF-P1 remains in Ruby |

---

## No Implementation Route Open

This card does not authorize and does not route to:

- Any change to field access handling in Ruby or Rust TC
- Any change to HOF lambda error propagation in Rust
- Any cast or type-narrowing operator
- Any validation receipt semantics
- Any new OOF codes

---

## Proof

```
proof runner:  igniter-lab/igniter-view-engine/proofs/verify_lab_unknown_field_access_p1.rb
checks:        35/35 PASS
sections:      A (source census) / B (Ruby TC direct) / C (Rust TC) /
               D (dynamic dispatch interaction) / E (output boundary) /
               F (safety policy) / G (closed surfaces)
```

---

## Open Routes (successors)

| Card | Scope |
|------|-------|
| LAB-RULE-ENGINE-BASELINE-P1 | Re-freeze rule_engine baseline post P-series |
| LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1 | Rust HOF lambda temp_errors vs Ruby propagation divergence |
| LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2 | Implementation planning for parametric container assignability |
