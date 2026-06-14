# LAB-RUST-TYPECHECKER-DECOMP-P1

**Status:** CLOSED — READINESS PROVED 60/60 — ROUTE: P2 (stdlib dispatch seam)  
**Route:** lab / compiler hygiene / Rust typechecker decomposition  
**Date:** 2026-06-14  
**Authority:** readiness + refactor plan only; no behavior change

## Goal

Decide and prove the first safe decomposition seam for the Rust lab compiler's
`typechecker.rs`, before the next wave of typechecker-heavy cards lands.

The pass pipeline is already modular (`lexer`, `parser`, `classifier`,
`typechecker`, `form_registry`, `form_resolver`, `emitter`, `assembler`,
`monomorphizer`, `multifile`, `liveness`). The problem is not compiler-pass
architecture. The problem is concentration inside `typechecker.rs`, especially
`infer_expr` and `typecheck_contract`.

This card is a readiness/planning card. It must not perform the refactor unless
explicitly authorized by a follow-up implementation card.

## Current Evidence

Observed source shape:

| File | Lines |
|---|---:|
| `src/typechecker.rs` | 5849 |
| `src/parser.rs` | 3201 |
| `src/classifier.rs` | 2052 |
| `src/emitter.rs` | 1804 |

Critical anchors in `typechecker.rs`:

| Function / region | Start line | Why it matters |
|---|---:|---|
| `typecheck_contract` | ~560 | large contract-level pass body |
| `infer_fold_call_type` | ~2328 | fold-specific helper already separable |
| `infer_expr` | ~2679 | giant expression dispatcher; main risk |
| stdlib call dispatch inside `infer_expr` | ~3011 | 38-ish call arms; future card hotspot |
| `"substring"` arm | ~3190 | recent stdlib surface pressure lands here |
| `"first" | "last"` arm | ~3248 | next Option/first-last track lands here |
| `"map"` arm | ~3447 | HOF/lambda diagnostics history lands here |
| `"fold"` arm | ~4014 | fold-struct and lowering parity pressure lands here |
| `operator_type` | ~4658 | numeric/text operator surface |
| `infer_match_expr` | ~5044 | Option/Result matchability will land here |
| `infer_field_expr_type` | ~5526 | record/output inference boundary |

## Recommended Decomposition Sequence

P1 should recommend the smallest behavior-preserving P2:

1. Extract stdlib call dispatch from `infer_expr` into a Rust submodule, likely
   `src/typechecker/stdlib_calls.rs` or an equivalent module layout.
2. Keep the public compiler API unchanged.
3. Preserve all diagnostics and statuses byte-for-byte where feasible.
4. Do not move parser, classifier, emitter, assembler, or app code.

Potential later modules, not P2 scope:

- `records.rs` for record literal inference, structural assignability, and field
  expression typing.
- `operators.rs` for `operator_type`.
- `match_expr.rs` for `infer_match_expr` and future Option/Result matchability.
- `infer_expr.rs` only after stdlib dispatch is extracted.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/lib.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/typechecker.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/emitter.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/app-pressure-recheck-wave-p11-2026-06-14-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/APP-RECHECK-WAVE-P11.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/dev-tutorial.md`
- Recent TC-heavy cards:
  - `LANG-FOLD-STRUCT-ACCUMULATOR-P3`
  - `LANG-FOLD-STRUCT-ACCUMULATOR-P4`
  - `LANG-STDLIB-COLLECTION-FIRST-LAST-OPTION-P1`
  - `LANG-STDLIB-OUTCOME-BIND-P1`
  - `LAB-DYNAMIC-CONTRACT-DISPATCH-P2`

## Proof Questions

1. Is the compiler pass pipeline already modular enough that this should remain
   an intra-typechecker refactor, not a crate/workspace split?
2. What are the exact line counts and largest function bodies in
   `typechecker.rs`?
3. Which future cards will collide inside `infer_expr` if no decomposition is
   done first?
4. Is stdlib call dispatch the safest first seam?
5. What data does the stdlib dispatch block need from `TypeChecker`, and can it
   be moved without changing ownership/public APIs?
6. Which diagnostics must be identical before/after a P2 extraction?
7. What fleet proof should P2 run: all 16 apps, exact statuses, exact diagnostic
   code/message/node sets, and `rule_engine` exact fail-closed trace?
8. Which outputs should P2 compare beyond diagnostics: manifest entrypoints,
   source hashes where stable, and SIR function names for stdlib calls?
9. Which surfaces must remain closed so this does not become a semantic change?
10. Should Ruby canon `typechecker.rb` be mirrored now, or deferred until the
    Rust lab seam proves useful?

## Deliverables

- Readiness / plan doc:
  `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-rust-typechecker-decomp-p1-v0.md`.
- Proof runner:
  `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/verify_rust_typechecker_decomp_p1.rb`.
- Update this card with closure summary.
- Portfolio index update after closure.

## Acceptance

- Proof runner target: at least 55 checks.
- Confirms `typechecker.rs` concentration with measured facts, not opinion.
- Confirms pass pipeline is already modular and should not be split into crates.
- Recommends one first implementation seam for P2.
- Defines a behavior-preserving P2 proof matrix over the 16-app Wave P11 fleet.
- Explicitly preserves `rule_engine` fail-closed diagnostics:
  - Rust: `OOF-P1 Unknown.action` + `OOF-TY1 expected RuleDecision, got Unknown`.
  - Ruby: not part of P2, but current parity context must be cited.
- Names future module candidates without authorizing them.
- No compiler source edits in P1 except proof/doc/card files.

## Closed Surfaces

- No `typechecker.rs` refactor in P1.
- No behavior changes.
- No diagnostic message/code changes.
- No parser, emitter, assembler, classifier, multifile, or app source edits.
- No Rust crate/workspace split.
- No Ruby canon `typechecker.rb` changes.
- No app migrations.
- No IO/runtime work.
- No formatting sweep or `cargo fmt` blanket run.

## Recommended P2 Shape

`LAB-RUST-TYPECHECKER-DECOMP-P2`: extract stdlib call dispatch from `infer_expr`
into a Rust submodule while preserving behavior exactly. P2 must run the full
16-app Wave P11 fleet and compare diagnostic sets before/after.

## Closure Summary (2026-06-14)

**READINESS PROVED 60/60.** Route: intra-typechecker decomposition (NOT a crate
split); P2 = extract the stdlib call dispatch from `infer_expr`.

### Measured facts (live source)
| Fact | Value |
|---|---:|
| `typechecker.rs` | 5849 ln (largest; parser 3201 / classifier 2052 / emitter 1804) |
| `infer_expr` | **1958 ln** (lines 2679–4637) — the main risk |
| `typecheck_contract` | 877 ln |
| infer_expr + typecheck_contract | ~48% of the file |
| dispatch arms (in infer_expr) | 71 (`"name" =>`), incl. all stdlib calls |
| pass modules in `lib.rs` | 11 → pipeline already modular |
| stdlib anchors | substring@3190, first/last@3248, map@3447, fold@4014 |

### 10 questions — answers
1. **Intra-typechecker**, not crate/workspace (11 pass modules already; ~17k single crate).
2. Facts above; biggest bodies infer_expr 1958 / typecheck_contract 877.
3. Collision: Fold P3/P4 → `"fold"`@4014; first-last-option → `"first"/"last"`@3248; outcome-bind → `infer_match_expr`@5044; substring → @3190; all inside one `infer_expr`.
4. **Yes — stdlib dispatch is the safest first seam** (contiguous, cohesive, exactly the hotspot).
5. Arms use `&self` helpers (`type_ir`/`type_name`/`get_param`/`structurally_assignable`/`type_shapes`) + a passed `type_errors`; movable to `infer_stdlib_call(&self,…)` with NO public-API/ownership change.
6. Identical `{rule,message,node}` sets + `status` per app; OOF-COL*/TY*/P1 unchanged.
7. 16-app Wave P11 fleet; exact diagnostics; **rule_engine fail-closed golden** captured live = Rust `OOF-P1 Unresolved field: Unknown.action` + `OOF-TY1 … expected RuleDecision, got Unknown` (exactly 2). 15/16 dual-clean.
8. Also compare manifest `entrypoint`, SIR stdlib-call fn-names, and the pinned companion hashes.
9. Closed: no diagnostic/message change, no other-pass/app edits, no crate split, no Ruby canon, no IO, no fmt sweep.
10. Ruby canon `typechecker.rb` mirror **deferred** (canon governance bar; mirror only after Rust seam proves useful).

### Recommended P2
`LAB-RUST-TYPECHECKER-DECOMP-P2`: extract stdlib dispatch → `src/typechecker/stdlib_calls.rs`,
behavior-preserving; `infer_expr` becomes a thin router; 16-app exact-diagnostic
parity proof via Open3/mktmpdir; rule_engine golden asserted. Later seams (named,
not authorized): `records.rs`, `operators.rs`, `match_expr.rs`, then `infer_expr.rs`.

### Deliverables
| Artefact | Path | Status |
|---|---|---|
| Plan doc | `lab-docs/lang/lab-rust-typechecker-decomp-p1-v0.md` | Written |
| Proof runner | `igniter-compiler/verify_rust_typechecker_decomp_p1.rb` | **60/60 PASS** (target ≥55) |
| This card | `.agents/work/cards/lang/LAB-RUST-TYPECHECKER-DECOMP-P1.md` | CLOSED |
| Portfolio index | `.agents/portfolio-index.md` | Updated |

### Acceptance
- ✅ ≥55 checks (60). ✅ Concentration confirmed by measurement. ✅ Pipeline modular → no crate split. ✅ One first seam recommended. ✅ Behavior-preserving P2 matrix over 16-app fleet defined. ✅ rule_engine fail-closed preserved (golden captured). ✅ Future modules named, not authorized. ✅ No compiler source edits in P1 (only proof/doc/card).

## Agent Recommendation

Best agent for P1: **Claude Opus 4.8**.

Why: this is a seam-design and risk-classification task. It benefits from deep
reading, conservative decomposition judgment, and precise proof-matrix design.
It should not be rushed as a mechanical refactor.

Fallback for P1: **Codex GPT 5.5** if Opus budget is reserved, but instruct it to
stop at readiness/proof and not edit `typechecker.rs`.

Best agent for P2: **Codex GPT 5.5** or **Claude Sonnet 4.6** after P1 closes.
P2 is mechanical Rust extraction plus parity proof. Avoid Gemini for the first
implementation slice unless it is paired with a strict proof-runner review.
