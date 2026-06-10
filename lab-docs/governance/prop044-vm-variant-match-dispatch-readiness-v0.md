# Lab Governance Doc: PROP-044 VM Variant/Match Dispatch Readiness & Risk Map

**Track:** variant-match-vm-dispatch-readiness-and-risk-map-v0
**Card:** PROP-044-P7-READINESS
**Category:** governance
**Date:** 2026-06-10
**Route:** GOVERNANCE / VM DISPATCH READINESS / NO IMPLEMENTATION
**Status:** CLOSED — readiness mapped; **DECISION: HOLD P7 (VM dispatch); open precursor P7a first**

---

## Decision (read this first)

**VM variant/match dispatch is NOT design-ready. P7 (VM dispatch) should HOLD.**

Not because VM dispatch is intrinsically hard — but because **the prerequisite does not
exist.** The PROP-044 variant/match feature lives **only in the Ruby canon pipeline**
(`igniter-lang`: PROP-044-P3 parser, P5 TypeChecker + OOF-KIND, P6 SemanticIR emitter). The
**entire Rust lab toolchain** — `igniter-compiler` *and* `igniter-vm`, which is what every VM
proof actually runs — has **zero** variant/match support at every layer. The Rust compiler
cannot even *parse* `variant`/`match` (it emits `OOF-G1` on every line), so **no variant SIR
node ever reaches the VM.** "Execute `variant_construct`/`match_node` in the VM" is therefore
not a VM task at all today — it is blocked behind re-implementing the whole front end in Rust.

**Recommended precursor route:**
- **PROP-044-P7a** — Rust compiler front-end variant/match + **SIR parity with the Ruby
  emitter** (lexer → parser → typechecker + OOF-KIND → emitter). No VM work. This is the real
  blocker; it mirrors PROP-044-P3→P6 but in Rust.
- **then PROP-044-P7b** — VM dispatch via **Path B** (lower `match_node` to `Record` + `if/else`,
  reusing existing opcodes; **no new opcode, no `Value::Variant`**).

The failure-taxonomy proposal-planning for sealed `Outcome[T,E]` should **WAIT** until at least
P7a lands.

Authority: lab-only readiness map. No VM/compiler edits, no opcodes, no `Value::Variant`, no
match lowering, no failure-taxonomy PROP, no sealed `Outcome[T,E]`, no canon/Covenant edits, no
Ruby/Rust `==` resolution, no public/stable API. `igniter-lang` is the language authority; Ch12
is referenced as proposed, not accepted canon.

---

## Grounding Evidence

`igniter-view-engine/proofs/survey_variant_match_vm_readiness.rb` — **15/15 PASS**. It compiles
variant/match source through the Rust compiler (→ `OOF-G1`, 0 contracts, no SIR), confirms the
Ruby front-end *does* parse variant declarations (the asymmetry), greps the actual Rust source
for the absent surfaces, and regression-anchors that the variant-free KDR P4 fixture still
compiles and routes in the VM. It is a read-only survey — no source edited.

---

## The Toolchain Asymmetry (the core finding)

There are **two** compiler implementations. Variant/match is implemented in **one**.

| Layer | Ruby canon (`igniter-lang`) | Rust lab (`igniter-compiler` / `igniter-vm`) |
|-------|------------------------------|----------------------------------------------|
| Lexer keywords `variant`/`match` | ✅ present | ❌ absent (`lexer.rs` KEYWORDS) → `OOF-G1` |
| Parser variant/match → AST | ✅ `parse_variant_decl`/`parse_match_expr` (P3) | ❌ `Expr` enum has no Match/Variant node |
| TypeChecker variant types + OOF-KIND1..5 | ✅ (P5, 75/75) | ❌ no variant/exhaustive/OOF-KIND |
| SemanticIR emitter `variant_declarations`/`variant_construct`/`match_node` | ✅ (P6, 50/50) | ❌ emits none |
| VM value representation | (n/a — Ruby has no VM) | ❌ `Value` enum has **no `Value::Variant`** |
| VM opcodes for match/variant | (n/a) | ❌ no `OP_MATCH`/`OP_PUSH_VARIANT` |
| VM compiler lowering of `match_node` | (n/a) | ❌ no handling → fails closed |

**Consequence:** the VM proofs (P2/P4) run the Rust toolchain. The Ruby emitter's
`match_node`/`variant_declarations` (P6) are produced in a **different** SemanticIR producer that
the VM proofs never consume. So the VM has *never* been handed a variant node — the Rust front
end rejects the source first. **The gap is a full Rust re-implementation of PROP-044-P3/P5/P6,
then VM dispatch — not "add an opcode."**

---

## VM Internals (surveyed, verbatim locations)

- **`Value` enum** (`igniter-vm/src/value.rs:7-16`): `Nil, Bool, Integer, Float, String,
  Decimal, Array, Record(BTreeMap)`. **No `Value::Variant`.** Result/Option are already emulated
  as `Record` + tag field — the existing precedent for Path B.
- **Opcodes** (`igniter-vm/src/instructions.rs`): ~34 ops incl. `OP_EQ`, `OP_JMP`, `OP_JMP_IF`,
  `OP_JMP_UNLESS`, `OP_PUSH_RECORD`, `OP_GET_FIELD`, `OP_AND`, `OP_OR`, `OP_NOT`. **No
  `OP_MATCH`/`OP_PUSH_VARIANT`/arm dispatch.**
- **Lowering** (`igniter-vm/src/compiler.rs`): `if_expr` → `OP_JMP_UNLESS`/`OP_JMP`; `record` →
  `OP_PUSH_RECORD`; `field_access` → `OP_GET_FIELD`; `==` → `OP_EQ`. **No `variant_construct`/
  `match_node` arm.** Unknown node kind → `"Unsupported AST expression kind"` (fails closed).
- **Fail-closed paths:** unknown opcode → `"Unknown instruction opcode"`; unknown node →
  `"Unsupported AST expression kind"`. The VM already refuses what it doesn't understand.

This is exactly the machinery P4 used to route `kind == "..."`: `OP_GET_FIELD` (tag) → `OP_EQ`
→ `OP_JMP_UNLESS`. **A lowered match is the proven P4 shape.**

---

## Answers to the 15 Design Questions

**1. Runtime representation of a variant value?** Path B (recommended): a `Record` with a
reserved discriminant field (`__arm`/`__variant`) plus payload fields — the existing Result/Option
emulation pattern. Path A: a new `Value::Variant { arm, payload }`. **No compile-time need for
`Value::Variant`** given Path B.

**2. What bytecode is needed?** Path B: **none new** — lower `match_node` to `OP_GET_FIELD` +
`OP_EQ` + `OP_JMP_UNLESS` chains; lower `variant_construct` to `OP_PUSH_RECORD` with the arm tag.
Path A: `OP_PUSH_VARIANT` + an `OP_MATCH_ARM` (or jump-table) + `Value::Variant`.

**3. Unit arms?** Path B: `Record` with only the discriminant field (`fields: []`, matching
PROP-044-P6 D4). Path A: `Variant` with empty payload.

**4. Record arms carry payload?** Path B: discriminant field + payload fields in the same
`Record`. Path A: `Variant` payload record.

**5. Match dispatch binds arm fields?** Path B: after the tag `OP_EQ` selects an arm, emit
`OP_GET_FIELD` for each bound field into the arm's compute scope (compiler-driven, the P5 per-arm
narrowed scopes lowered to field reads). Path A: `OP_MATCH_ARM` binds.

**6. Wildcard `_`?** Path B: the final `else` branch with no tag comparison. Path A: a catch-all
arm.

**7. Exhaustiveness at runtime?** **Not represented at runtime.** Exhaustiveness is a *typecheck*
property (OOF-KIND1). The runtime carries no exhaustiveness check.

**8. Should the VM trust TypeChecker exhaustiveness?** **Yes** — but the lowered `if/else` chain
**must end in an explicit fail-closed default** (`"non-exhaustive match at runtime"` error), *not*
a silent fallthrough/`Nil`. The VM trusts the TC for completeness yet stays defensively
fail-closed — this is the No-Upward-Coercion principle applied to dispatch (a missed arm must
never resolve to a fabricated value).

**9. Malformed SemanticIR reaching the VM?** Already handled — fails closed
(`"Unsupported AST expression kind"` / `"Unknown instruction opcode"`). Path B inherits this for
free (the VM sees only `Record`/`if`); Path A must add explicit fail-closed guards for malformed
variant nodes.

**10. Can `match_node` lower to existing `if/else` safely?** **Yes — already proven.** P4 executed
the exact lowered shape (tag `==` chains over record fields, nested `if/else`, fail-closed default)
in the VM, 46/46. Lowering match → tag-`if/else` is a proven-safe transformation.

**11. Does lowering reproduce the Ruby/Rust `==` divergence, or avoid it?** **Avoids it at the
source/typecheck layer.** The divergence is a *TypeChecker* check on **source** operators
(`OOF-TY0 "Unsupported operator: =="` in Ruby). Lowering happens **after** typecheck, and the user
writes `match`, never `==` — so the operator check never fires on lowered code. **But** this only
holds if both Ruby and Rust lower match *consistently* (parity), which is why P7a's SIR-parity
proof matters. Variant/match does **not fix** the underlying `==` divergence (hand-written KDR
routing still hits it — that's STAB-P4's); it makes the divergence **irrelevant for outcome
routing** by giving an arm-based surface instead of string `==`.

**12. Which layer owns arm identity?** Path B: the **compiler** owns it (lowers arm → tag string).
Path A: the **value representation** owns it (`Value::Variant.arm`). Recommended: compiler-owned
(Path B) — smallest surface; the *typechecker* is where arm identity is actually enforced.

**13. Can `variant_construct`/`match_node` execute without changing parser/TypeChecker/SemanticIR?**
**No — emphatically.** The Rust toolchain has none of it; the Rust parser rejects the source
(`OOF-G1`) before anything reaches emit or VM. P7 requires Rust **lexer + parser + typechecker +
emitter** changes first, then VM. It does **not** require Ruby canon changes (Ruby already has it).

**14. Regressions to protect?** All existing VM proofs — record construction / field access /
nested (P3 record-vm), `map_get` (VM-MAP-P1), `if/else` lowering, the epistemic KDR proofs (P2 54/54,
P4 46/46), query/rack/sidekiq. Plus **Ruby↔Rust SIR parity for non-variant programs** (P7a must not
perturb existing SIR shapes).

**15. Exact safe P7 implementation card?** Not a single "VM variant dispatch" card. Decompose:
**P7a** (Rust front-end + SIR parity, no VM) then **P7b** (VM lowering, Path B). See Proof Matrix.

---

## Path Comparison

| Dimension | Path A — native `Value::Variant` + opcodes | Path B — lower to `Record` + `if/else` *(recommended)* |
|-----------|--------------------------------------------|--------------------------------------------------------|
| New VM value kind | `Value::Variant` (new) | none — reuse `Record` |
| New opcodes | `OP_PUSH_VARIANT`, `OP_MATCH_ARM` (≥2) | none — reuse `GET_FIELD`/`EQ`/`JMP_UNLESS`/`PUSH_RECORD` |
| VM surface touched | `value.rs`, `instructions.rs`, `vm.rs`, `compiler.rs` | `compiler.rs` only (lowering) |
| Runtime identity | true variant identity | string-tag dispatch (renames KDR at runtime) |
| Already proven to execute? | no | **yes — P4 executed the lowered shape (46/46)** |
| Regression risk | high (new value kind touches every `Value` match) | low (no `Value` change; additive lowering) |
| Removes string-dispatch fragility | at runtime **and** typecheck | at **source/typecheck** only (runtime still tag `==`) |
| Implementation risk | high | low |

**Recommendation: Path B.** The epistemic value of variant/match — exhaustiveness (forces handling
`still_unknown`/`reconciliation_error`), per-arm narrowing (prevents wrong-arm field access),
making the forbidden transitions unrepresentable — lives at the **typecheck** layer, not the
runtime representation. Path B captures all of that (it inherits P5's OOF-KIND once P7a lands) at a
fraction of the VM risk, and P4 already proved the lowered runtime executes. The "string dispatch is
fragile" critique is answered at the surface: the user writes an *exhaustive, narrowed* `match`, not
hand-rolled `kind == "..."` — the fragility (typos, missed arms) is removed where it actually bites.
Reconsider Path A only if a concrete need for runtime variant identity emerges (e.g. reflection,
serialization round-trips that must distinguish a variant from a same-shaped record).

### Comparison against current KDR

KDR works in the VM today, uses String `kind`, is unenforced at runtime, and P4 showed it executes
but surfaced the operator divergence. **Path B is KDR-at-runtime with enforcement-at-typecheck** —
it does not remove string dispatch from the *bytecode*, but it removes the *unenforced, typo-prone,
non-exhaustive* nature of KDR from the *source*. That is the right trade: enforce where errors are
made (authoring), stay cheap where it runs (dispatch).

---

## Proof Matrix P7 Implementation Should Require

**P7a — Rust front-end variant/match + SIR parity (no VM):**

| Group | What it must prove |
|-------|--------------------|
| P7a-LEX | `variant`/`match` lex as keywords; non-variant programs unaffected |
| P7a-PARSE | variant decls + match exprs parse into the Rust `Expr`/AST; arm patterns + bindings |
| P7a-TYPE | variant types resolve; match arm typing; **OOF-KIND1..5 fire identically to Ruby (P5)** |
| P7a-EMIT | emitter produces `variant_declarations`/`variant_construct`/`match_node` |
| **P7a-PARITY** | **Rust SIR structurally equals Ruby SIR** (P6) on a shared variant fixture (the load-bearing check) |
| P7a-REG | every existing Rust proof green; non-variant SIR byte-stable |

**P7b — VM dispatch via Path B (after P7a):**

| Group | What it must prove |
|-------|--------------------|
| P7b-CONSTRUCT | `variant_construct` lowers to `OP_PUSH_RECORD` + tag; VM builds the value |
| P7b-MATCH | `match_node` lowers to `OP_GET_FIELD`/`OP_EQ`/`OP_JMP_UNLESS`; correct arm selected |
| P7b-BIND | arm payload fields bind via `OP_GET_FIELD` into arm scope |
| P7b-WILDCARD | `_` executes as final else |
| P7b-FAILCLOSED | non-matching value (malformed/over-trusted) → explicit runtime error, never `Nil` |
| **P7b-EQUIV** | **a variant `Outcome` routing fixture yields the SAME terminal actions as the P4 KDR `RouteReceipt`** (equivalence to the proven KDR behavior) |
| P7b-REG | all VM proofs green (record/map/if-else/P2/P4/query/rack/sidekiq) |

---

## Explicit Answers (card-required)

- **Is VM variant dispatch design-ready?** **No.** Blocked behind a missing Rust front end.
- **Which implementation path is recommended?** **Path B** (lower to `Record` + `if/else`).
- **Are new VM opcodes required?** **No** (Path B). Path A would need ≥2.
- **Is `Value::Variant` required?** **No** (Path B).
- **Can `match_node` lower to existing branch instructions safely?** **Yes** — P4 proved the exact
  lowered shape executes (46/46).
- **Does the recommended path avoid or preserve the Ruby/Rust `==` divergence?** **Avoids** it for
  outcome routing (user writes `match`, not `==`; lowering is post-typecheck). It does **not fix**
  the underlying divergence (STAB-P4 owns that).
- **Does P7 require Rust compiler changes, VM changes, or both?** **Both** — Rust compiler front end
  first (P7a), then VM lowering (P7b).
- **Does P7 require Ruby canon changes?** **No** — Ruby already has variant/match (PROP-044-P3/P5/P6).
- **Does P7 authorize failure-taxonomy PROP?** **No.**
- **Does P7 authorize sealed `Outcome[T,E]`?** **No.**
- **What exact proof matrix should P7 require?** See Proof Matrix (P7a + P7b above).
- **Should failure-taxonomy proposal-planning open after readiness, or wait?** **Wait** — until at
  least P7a (Rust front-end + SIR parity) lands; a sealed `Outcome[T,E]` cannot execute in the lab
  toolchain before then.

---

## Closed Surfaces (no route opens these here)

VM/compiler source edits; `Value::Variant`; new opcodes; match lowering; failure-taxonomy PROP;
sealed `Outcome[T,E]`; canon spec/Covenant edits; VM runtime authority for variant/match; resolving
the Ruby/Rust `==` divergence (STAB-P4); the PROP-035 numbering collision (STAB-P4); public/stable
API; promoting lab KDR convention into canon; changing `Result`/`Option`.

---

## P7a Implementation Card Outline (if/when authorized — NOT authorized here)

```
Card:  PROP-044-P7a  (proposed; requires explicit auth)
Goal:  Implement variant/match in the Rust igniter-compiler front end (lexer→parser→
       typechecker+OOF-KIND→emitter) to SIR PARITY with the Ruby emitter (PROP-044-P6).
       NO VM work. NO sealed Outcome[T,E]. NO failure-taxonomy PROP.
Scope: igniter-compiler/src/{lexer.rs,parser.rs,typechecker.rs,emitter.rs} only.
Gate:  P7a-PARITY (Rust SIR ≡ Ruby SIR on shared variant fixture) + OOF-KIND parity + all
       existing Rust proofs green + non-variant SIR byte-stable.
Then:  PROP-044-P7b (VM dispatch, Path B) — separate card, separate auth.
```

---

## Gap Packet

```
readiness:  prop044-vm-variant-match-dispatch-readiness / v0
status:     CLOSED — readiness mapped; DECISION = HOLD P7; open P7a precursor
authority:  governance / lab_only
date:       2026-06-10
survey:     survey_variant_match_vm_readiness.rb 15/15 PASS

core_finding: variant/match exists ONLY in Ruby canon (PROP-044-P3/P5/P6).
              Rust lab toolchain (igniter-compiler + igniter-vm) = ZERO support at every layer.
              Rust compiler rejects variant/match source with OOF-G1 → no SIR reaches VM.
              "VM dispatch" is blocked behind a full Rust front-end re-implementation.

vm_internals: Value enum 8 kinds, no Value::Variant; ~34 opcodes, no OP_MATCH;
              compiler.rs no variant_construct/match_node; fails closed on unknown nodes.
              Proven primitives for Path B: OP_GET_FIELD + OP_EQ + OP_JMP_UNLESS + OP_PUSH_RECORD.

design_answers:
  vm_dispatch_ready:        NO
  recommended_path:         Path B (lower match_node → Record + if/else)
  new_opcodes_required:     NO (Path B)
  value_variant_required:   NO (Path B)
  match_lowers_to_ifelse:   YES (P4 proved the lowered shape executes, 46/46)
  avoids_eq_divergence:     YES for outcome routing (post-typecheck lowering); does NOT fix it
  requires_rust_changes:    YES (compiler front end + VM)
  requires_ruby_changes:    NO
  authorizes_failuretax_prop: NO
  authorizes_sealed_outcome:  NO
  exhaustiveness_runtime:   NOT represented; VM trusts TC but lowers to fail-closed default
  arm_identity_owner:       compiler (Path B)

decision:    HOLD P7 (VM dispatch).
precursor:   PROP-044-P7a (Rust front-end + SIR parity, no VM) → then PROP-044-P7b (VM Path B).
failure_taxonomy_planning: WAIT until ≥ P7a lands.
regression:  KDR P2 54/54 + P4 46/46 + P3 43/43 green; git only-new-files.
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. Readiness/risk map + read-only
survey. No VM/compiler source edited; no `Value::Variant`; no opcodes added; no match lowering
implemented; no failure-taxonomy PROP authored; no sealed `Outcome[T,E]` implemented. No canon spec
or Covenant edits. No VM runtime authority claimed for variant/match. The Ruby/Rust `==` divergence
is described, not resolved (STAB-P4). The PROP-035 numbering collision is not resolved (STAB-P4).
`Result`/`Option` untouched. Ch12 treated as proposed, not accepted canon. Old Ruby framework
surfaces not used as language authority. Lab behavior not accepted as canon. This doc informs future
gate decisions; it does not make them.
