# Card: PROP-044-P7-READINESS
**Category:** governance
**Track:** variant-match-vm-dispatch-readiness-and-risk-map-v0
**Status:** CLOSED — READINESS MAPPED
**Gate result:** DECISION = HOLD P7 (VM dispatch); open P7a precursor — survey 15/15 PASS
**Date closed:** 2026-06-10
**Route:** GOVERNANCE / VM DISPATCH READINESS / NO IMPLEMENTATION

---

## Goal

Map the readiness, sequencing, and risk surface for executing `variant_construct` and
`match_node` in the lab VM. Answer what a P7 implementation would require before any runtime work
is authorized.

---

## Decision

**HOLD P7 (VM variant/match dispatch). It is NOT design-ready.** The blocker is not VM difficulty —
it is that **variant/match exists ONLY in the Ruby canon pipeline** (PROP-044-P3/P5/P6) and the
**entire Rust lab toolchain** (`igniter-compiler` + `igniter-vm`, which is what the VM proofs run)
has **zero** support at every layer. The Rust compiler rejects `variant`/`match` source with
`OOF-G1` before any node reaches the VM. "VM dispatch" is blocked behind a full Rust front-end
re-implementation.

**Precursor route:** PROP-044-P7a (Rust front-end variant/match + SIR parity with Ruby, no VM) →
then PROP-044-P7b (VM dispatch, Path B). Failure-taxonomy proposal-planning **waits** until ≥ P7a.

---

## Depends On

| Card | Status |
|------|--------|
| PROP-044-P1..P6 | ✅ DONE — variant/match in Ruby canon (parser/TC/OOF-KIND/SIR emitter) |
| LAB-EPISTEMIC-OUTCOME-P4 | ✅ DONE — KDR VM routing (46/46); surfaced ==/|| divergence |
| LAB-RESULT-ENVELOPE-P2 | ✅ DONE — KDR kind-discriminant baseline |
| LAB-VM-MAP-P1 | ✅ DONE — map_get VM runtime |
| LAB-RECORD-VM-P3 | ✅ DONE — nested record field values |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Readiness/risk map | `lab-docs/governance/prop044-vm-variant-match-dispatch-readiness-v0.md` | ✅ DONE |
| Survey script (15 checks) | `igniter-view-engine/proofs/survey_variant_match_vm_readiness.rb` | ✅ DONE |
| This card | `.agents/work/cards/governance/PROP-044-P7-READINESS.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Core Finding — Toolchain Asymmetry

| Layer | Ruby canon | Rust lab |
|-------|-----------|----------|
| lexer `variant`/`match` keywords | ✅ | ❌ → OOF-G1 |
| parser variant/match AST | ✅ (P3) | ❌ no Expr node |
| typechecker variant + OOF-KIND1..5 | ✅ (P5) | ❌ |
| SIR emitter variant_declarations/variant_construct/match_node | ✅ (P6) | ❌ |
| VM `Value::Variant` | n/a | ❌ (8 kinds, none) |
| VM match opcode | n/a | ❌ (~34 ops, none) |
| VM `match_node` lowering | n/a | ❌ (fails closed) |

The VM proofs run the Rust toolchain → the VM has never been handed a variant node. P7 = re-implement
PROP-044-P3/P5/P6 in Rust, **then** VM dispatch.

---

## Path Comparison (summary)

| | Path A native `Value::Variant`+opcodes | **Path B** lower→Record+if/else (recommended) |
|-|----------------------------------------|----------------------------------------------|
| new opcodes | ≥2 | **none** |
| `Value::Variant` | yes | **no** |
| VM surface | value.rs+instructions.rs+vm.rs+compiler.rs | **compiler.rs only** |
| proven to execute? | no | **yes — P4 ran the lowered shape (46/46)** |
| risk | high | **low** |
| removes string dispatch | runtime+typecheck | **source/typecheck** (runtime still tag ==) |

Recommend **Path B**: the epistemic value (exhaustiveness, narrowing, No-Upward-Coercion) is a
**typecheck** property; Path B inherits it (via P5/P7a OOF-KIND) at minimal VM risk and P4 already
proved the lowered runtime executes.

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| VM variant dispatch design-ready? | **NO** |
| Recommended path? | **Path B** (lower to Record + if/else) |
| New VM opcodes required? | **NO** (Path B) |
| `Value::Variant` required? | **NO** (Path B) |
| `match_node` lowers to branch instrs safely? | **YES** — P4 proved the lowered shape (46/46) |
| Avoids or preserves the ==/|| divergence? | **Avoids** for outcome routing (post-typecheck; user writes match not ==); does NOT fix it (STAB-P4) |
| Requires Rust compiler changes, VM changes, or both? | **Both** — front end (P7a) then VM (P7b) |
| Requires Ruby canon changes? | **NO** |
| Authorizes failure-taxonomy PROP? | **NO** |
| Authorizes sealed `Outcome[T,E]`? | **NO** |
| Proof matrix P7 should require? | P7a (LEX/PARSE/TYPE/EMIT/**PARITY**/REG) + P7b (CONSTRUCT/MATCH/BIND/WILDCARD/FAILCLOSED/**EQUIV**/REG) |
| Failure-taxonomy planning open now or wait? | **WAIT** until ≥ P7a lands |

---

## Gap Packet

```
readiness:  prop044-vm-variant-match-dispatch-readiness / v0
status:     CLOSED — DECISION = HOLD P7; open P7a precursor
authority:  governance / lab_only
date:       2026-06-10
survey:     survey_variant_match_vm_readiness.rb 15/15 PASS

core:       variant/match = Ruby-canon-only (PROP-044-P3/P5/P6); Rust toolchain ZERO support;
            Rust rejects source (OOF-G1) → no variant SIR reaches VM.
path_b_primitives: OP_GET_FIELD + OP_EQ + OP_JMP_UNLESS + OP_PUSH_RECORD (all present; P4-proven)

decision:   HOLD P7 (VM dispatch)
precursor:  PROP-044-P7a (Rust front-end + SIR PARITY, no VM) → PROP-044-P7b (VM Path B)
failure_taxonomy_planning: WAIT until ≥ P7a

answers:    ready NO | path B | new_opcodes NO | Value::Variant NO | match→ifelse YES |
            avoids_eq_divergence YES(routing)/not-fixed | rust_changes BOTH | ruby_changes NO |
            authorizes_prop NO | authorizes_sealed_outcome NO | exhaustiveness=typecheck-only,
            VM trusts TC + fail-closed default | arm_identity=compiler-owned

regression: KDR P2 54/54 + P4 46/46 + P3 43/43 green; git only-new-files
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. Readiness map + read-only survey.
No VM/compiler source edited; no `Value::Variant`; no opcodes; no match lowering; no failure-taxonomy
PROP; no sealed `Outcome[T,E]`. No canon spec or Covenant edits. No VM runtime authority claimed for
variant/match. Ruby/Rust `==` divergence described, not resolved (STAB-P4). PROP-035 numbering
collision not resolved (STAB-P4). `Result`/`Option` untouched. Ch12 treated as proposed, not accepted
canon. Old Ruby framework surfaces not used as language authority. Lab behavior not accepted as canon.
This card informs future gate decisions; it does not make them.
