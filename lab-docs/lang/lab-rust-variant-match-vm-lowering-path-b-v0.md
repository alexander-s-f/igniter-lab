# Lab: Rust Variant/Match VM Lowering — Path B — v0

**Card:** LAB-VARIANT-VM-P1  
**Status:** Proved (42/42 PASS)  
**Date:** 2026-06-10  
**Route:** LAB VM LOWERING / PATH B / NO NEW OPCODES  
**Authority:** lab_only — not canon, not production

---

## Motivation

LAB-VARIANT-RUST-P1 (39/39 PASS) implemented variant/match support in the Rust lab
compiler through SemanticIR emission, achieving SIR parity with Ruby PROP-044-P6.
But the VM could not execute variant/match contracts — the compiler produced correct SIR
but the VM compiler (`igniter-vm/src/compiler.rs`) had no lowering for `variant_construct`
or `match_node` nodes.

This doc records Path B: lowering variant/match to existing VM opcodes with no new
opcode definitions, no `Value::Variant`, and no changes to the closed VM surfaces
(`instructions.rs`, `vm.rs`, `value.rs`).

---

## Scope

**Authorized (writes):**
- `igniter-vm/src/compiler.rs` — two new arms in `compile_expr`
- `igniter-view-engine/fixtures/variant_match/` — 7 new VM fixtures (11–17)
- `igniter-view-engine/proofs/verify_lab_variant_vm_p1.rb`
- `igniter-lab/lab-docs/lang/lab-rust-variant-match-vm-lowering-path-b-v0.md`
- `igniter-lang/.agents/work/cards/lang/LAB-VARIANT-VM-P1.md`
- `igniter-lab/.agents/portfolio-index.md`

**Closed (no writes):**
- `igniter-vm/src/instructions.rs` — no new opcodes
- `igniter-vm/src/vm.rs` — no new dispatch branches
- `igniter-vm/src/value.rs` — no `Value::Variant`
- Ruby canon pipeline — unchanged
- `Outcome[T,E]` — not sealed
- Failure taxonomy — not authored

---

## Path B Design

### variant_construct → OP_PUSH_RECORD with discriminant fields

A `variant_construct` node (e.g. `Fulfilled {}` or `Tagged { tag }`) lowers to an
ordinary record containing two compiler-owned discriminant fields:

| Field | Value | Purpose |
|-------|-------|---------|
| `__arm` | arm name (String) | discriminant for match routing |
| `__variant` | variant name (String) | diagnostic / identity |

Plus any payload fields verbatim. All keys are sorted before emission to satisfy
`OP_PUSH_RECORD`'s sorted-key invariant.

**SIR shape consumed:**
```json
{
  "kind": "variant_construct",
  "arm": "Fulfilled",
  "variant": "OrderStatus",
  "fields": {},
  "resolved_type": { "name": "OrderStatus", "params": [] }
}
```

**Emitted bytecode for `Fulfilled {}`:**
```
OP_PUSH_LIT  "Fulfilled"    -- __arm
OP_PUSH_LIT  "OrderStatus"  -- __variant
OP_PUSH_RECORD 2, "__arm", "__variant"
```

**Runtime result:** `Value::Record({"__arm": "Fulfilled", "__variant": "OrderStatus"})`

### match_node → OP_GET_FIELD + OP_EQ + OP_JMP_UNLESS chain

A `match_node` (top-level) or `match_expr` (nested in arm body) lowers to a
discriminant-compare chain:

1. Compile subject once → store in dedicated temp register `R_subject`.
2. For each non-wildcard arm:
   - Load `R_subject`, `OP_GET_FIELD "__arm"` → push discriminant string
   - `OP_PUSH_LIT arm_name`, `OP_EQ` → bool
   - `OP_JMP_UNLESS <next_arm_ip>` — skip if not this arm
   - Extract payload bindings into scoped temp registers
   - Compile arm body (result left on stack)
   - Remove bindings from scope
   - `OP_JMP <end_ip>` — skip remaining arms
3. Wildcard arm: compile body, `OP_JMP <end_ip>`.
4. No-match fallback (no wildcard): `OP_UNSUPPORTED` — fail closed.
5. Patch all end-jumps to current IP.

**SIR shape consumed:**
```json
{
  "kind": "match_node",
  "subject": { "kind": "ref", "name": "signal" },
  "arms": [
    { "pattern": { "arm": "Green", "bindings": [], "wildcard": false },
      "body": { "kind": "literal", "value": "proceed", "type_tag": "String" } }
  ],
  "has_wildcard": false
}
```

**Emitted bytecode for `match signal { Green {} => "proceed" ... }`:**
```
OP_LOAD_REF  "signal"        -- compile subject
OP_STORE_REG R_subject       -- store in temp register

-- arm Green:
OP_LOAD_REG  R_subject
OP_GET_FIELD "__arm"
OP_PUSH_LIT  "Green"
OP_EQ
OP_JMP_UNLESS <next_arm>     -- skip if not Green
OP_PUSH_LIT  "proceed"       -- arm body
OP_JMP       <end>

-- ... next arms ...

OP_UNSUPPORTED               -- fail-closed (no wildcard)

-- end:
```

### `match_expr` — the nested match alias

The Rust parser's `Expr::MatchExpr` is internally tagged `#[serde(rename = "match_expr")]`.
The emitter renames top-level `annotated_expr` from `match_expr` → `match_node`
(`lower_annotated_expr`). But arm bodies in SIR come from `annotate_expr_with_type`
(raw AST serialization), so nested match expressions in arm bodies have `kind: "match_expr"`.

The VM compiler handles both names with a single combined arm:
```rust
"match_node" | "match_expr" => { ... }
```

The raw AST `MatchPattern` fields (`wildcard`, `arm`, `bindings`) match the enriched SIR
pattern fields exactly. The raw AST `MatchExpr` fields (`subject`, `arms`) also match.
The only structural difference is that the raw `match_expr` lacks `has_wildcard` —
handled by `unwrap_or(false)`, which defaults to fail-closed (OP_UNSUPPORTED appended).
Since nested matches are typechecked for exhaustiveness, OP_UNSUPPORTED on a fully
exhaustive nested match is unreachable dead code.

---

## Fixtures

| File | Purpose |
|------|---------|
| `11_vm_variant_construct_basic.ig` | variant_construct → Record with __arm/__variant |
| `12_vm_match_unit_arms.ig` | unit arm matching (3 arms, no wildcard) |
| `13_vm_match_payload_bindings.ig` | payload field binding extraction via ref |
| `14_vm_match_wildcard.ig` | wildcard arm catches non-listed arms |
| `15_vm_match_two_nodes.ig` | two match nodes + concat — register isolation |
| `16_vm_match_kdr_equivalence.ig` | ReconciliationOutcome → P4 KDR routing shape |
| `17_vm_nested_match.ig` | nested match_expr in arm body — kinds=match_expr |

---

## VM Input Convention

Variant values passed as VM inputs are records with `__arm` and `__variant` discriminants:

```json
{ "signal": { "__arm": "Green", "__variant": "SignalKind" } }
```

Payload fields are included inline:

```json
{ "event": { "__arm": "Tagged", "__variant": "TaggedEvent", "tag": "hello" } }
```

This is consistent with the variant_construct lowering — a variant is always a Record.

---

## Fail-Closed Invariants

1. **Unknown arm on no-wildcard match** → `OP_UNSUPPORTED` fires → `status: "error"` with
   message "Decoded unsupported selected-path bytecode instruction". Never silent Nil.

2. **Malformed variant (missing `__arm`)** → `OP_GET_FIELD "__arm"` returns an error
   with the available fields listed. Not coerced to any arm or to Nil.

3. **Wildcard match** → final arm always fires; `OP_UNSUPPORTED` is not emitted.

---

## Proof Result

**42/42 PASS** — `ruby igniter-view-engine/proofs/verify_lab_variant_vm_p1.rb`

| Section | Checks | Description |
|---------|--------|-------------|
| VVM-COMPILE | 7 | All 7 VM fixtures compile |
| VVM-CONSTRUCT | 3 | variant_construct → __arm/__variant Record |
| VVM-MATCH | 5 | Unit arm selection |
| VVM-BIND | 3 | Payload field binding |
| VVM-WILDCARD | 3 | Wildcard routing |
| VVM-FAILCLOSED | 3 | Fail-closed on unknown/malformed input |
| VVM-TWONODES | 3 | Two match nodes, register isolation |
| VVM-NESTED | 4 | Nested match_expr in arm body |
| VVM-EQUIV | 6 | KDR routing equivalence |
| VVM-CLOSED | 5 | VM surfaces closed |

---

## What This Proves

- `variant_construct` lowers correctly to `OP_PUSH_RECORD` with `__arm`/`__variant` discriminants
- `match_node` lowers to `OP_GET_FIELD`/`OP_EQ`/`OP_JMP_UNLESS` chain — no new opcodes
- Payload field bindings extract from the variant record and are available in arm body scope
- Wildcard arms catch unmatched inputs; no-wildcard matches are fail-closed
- Two match nodes in one contract use independent temp registers — no register collision
- Nested `match_expr` (raw AST kind from arm bodies) is handled identically to `match_node`
- The VM correctly routes 5 reconciliation outcomes per the P4 KDR table
- `instructions.rs`, `vm.rs`, `value.rs` are closed — zero changes

## What This Does NOT Prove

- `Outcome[T,E]` as an enforced variant type — not sealed, not introduced
- Production runtime support for variant/match — lab only
- Public/stable API — no API surface added
- Any canon authority — Ruby canon pipeline unchanged
- Sealed failure taxonomy — not authored

---

## Promotion Boundary

| Layer | Status |
|-------|--------|
| Ruby canon parser (PROP-044-P3) | ✅ 50/50 |
| Ruby canon typechecker + OOF-KIND1..5 (PROP-044-P5) | ✅ 75/75 |
| Ruby canon SIR emitter (PROP-044-P6) | ✅ 50/50 |
| Rust front-end + SIR parity (LAB-VARIANT-RUST-P1) | ✅ 39/39 |
| **Rust VM match lowering Path B (this)** | ✅ 42/42 |
| Sealed Outcome[T,E] enforcement (PROP-044-P7) | 🔒 Next gate |
