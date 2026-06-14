# LAB-RUST-TYPECHECKER-DECOMP-P1 — Readiness & Decomposition Plan

**Status:** CLOSED — READINESS PROVED 60/60 — ROUTE: P2 (extract stdlib dispatch seam)
**Track:** lab / compiler hygiene / Rust typechecker decomposition
**Date:** 2026-06-14
**Authority:** readiness + refactor-plan only — NO behavior change, NO `typechecker.rs` edit

---

## 0. TL;DR

The Rust lab compiler's **pass pipeline is already modular** (11 modules in
`lib.rs`) — this is **not** a crate/workspace problem. The genuine debt is
**concentration inside one file, `typechecker.rs` (5849 lines)**, dominated by two
god-functions: **`infer_expr` (1958 lines)** and **`typecheck_contract` (877
lines)** — together ~48% of the file. The 71 dispatch arms (incl. all stdlib
calls) live inside `infer_expr`, and **every queued typechecker card lands there**.

**Route:** an intra-typechecker submodule split, smallest-seam-first.
**P2 = extract the stdlib call dispatch from `infer_expr` into
`src/typechecker/stdlib_calls.rs`**, behavior-preserving, proved against the
16-app Wave P11 fleet with exact diagnostic sets and `rule_engine` fail-closed
preserved.

---

## 1. Measured facts (not opinion)

| Fact | Value | Source |
|---|---:|---|
| `typechecker.rs` | **5849 ln** | largest file; parser 3201, classifier 2052, emitter 1804 |
| `infer_expr` | **1958 ln** (lines 2679–4637) | the main risk |
| `typecheck_contract` | **877 ln** (from 560) | second concentration |
| infer_expr + typecheck_contract | **~48%** of the file | — |
| impl blocks | 2 (a god-impl) | — |
| dispatch arms | 71 (`"name" =>`), incl. all stdlib calls inside `infer_expr` | — |
| pass modules in `lib.rs` | **11** (lexer…liveness) | pipeline already modular |
| whole compiler | ~16,820 ln single crate | crate split unwarranted |

Stdlib-dispatch anchors inside `infer_expr`: `"substring"`@3190, `"first"/"last"`@3248,
`"map"`@3447, `"fold"`@4014 (Fold P3 landed here, growing the arm). Other anchors:
`infer_fold_call_type`@2328, `operator_type`@4658, `infer_match_expr`@5044,
`infer_field_expr_type`@5526.

---

## 2. The ten proof questions

**Q1. Crate/workspace split or intra-typechecker refactor?**
**Intra-typechecker.** `lib.rs` already declares 11 pass modules; each pass is its
own file. A crate/workspace split of a ~17k-line single crate would slow iteration
and the dual-toolchain parity loop for no structural gain. The unit of work is
**Rust submodules under the typechecker pass**, not crates.

**Q2. Exact line counts / largest bodies?**
See §1. `typechecker.rs` 5849; `infer_expr` 1958; `typecheck_contract` 877;
`infer_field_expr_type` 245; `operator_type` 226; `infer_match_expr` 171;
`infer_fold_call_type` 135.

**Q3. Which future cards collide inside `infer_expr`?**
All of the queued TC-heavy work targets arms inside the single `infer_expr` body:
- `LANG-FOLD-STRUCT-ACCUMULATOR-P3/P4` → the `"fold"` arm (@4014) + fold helper.
- `LANG-STDLIB-COLLECTION-FIRST-LAST-OPTION-P1` → the `"first"/"last"` arm (@3248).
- `LANG-STDLIB-OUTCOME-BIND-P1` → `infer_match_expr` (@5044) + Result arms.
- substring/string pressure → the `"substring"` arm (@3190).
- `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` policy → the `call_contract` region.
≥3 independent edits in one 1958-line function = merge/regression risk →
**split-first** de-risks the wave.

**Q4. Is stdlib call dispatch the safest first seam?**
**Yes.** It is a **contiguous arm block** (substring→map→fold span >100 lines, all
inside `infer_expr`), cohesive (one concern: "type a stdlib call"), and exactly the
hotspot the queued cards edit. Extracting it shrinks `infer_expr` to a thin router.

**Q5. What does the dispatch need from `TypeChecker`; can it move without API change?**
The arms read via `&self` helpers (`self.type_ir`, `self.type_name`, `get_param`,
`structurally_assignable`, `type_shapes`) and push into a passed
`type_errors: &mut Vec<…>` accumulator, dispatching on `typed_args`/`resolved_type`.
That signature is movable: a `stdlib_calls.rs` hosting
`fn infer_stdlib_call(&self, fn_name, args, typed_args, type_errors, …) -> Resolved`
keeps ownership and the public compiler API unchanged. No `&mut self` field
mutation inside the arms blocks a `&self` extraction.

**Q6. Which diagnostics must be identical before/after P2?**
Every app's full `{rule, message, node}` diagnostic set, byte-for-byte, plus
compile `status`. Specifically the OOF families produced by stdlib calls
(OOF-COL*, OOF-TY*, OOF-P1) must be unchanged.

**Q7. What fleet proof must P2 run?**
The **16-app Wave P11 fleet**: `advanced_logistics, arch_patterns, bloom_filter,
dataframes, decision_tree, dsa, igniter_parser, neural_net, sim_framework,
vector_editor, vector_math, rule_engine, trade_robot, air_combat, lead_router,
call_router`. For each: exact `status` + exact diagnostic `{rule,message,node}` set
before vs after. **`rule_engine` fail-closed must be preserved exactly** — captured
live in this P1 as the golden:
- Rust: `OOF-P1 Unresolved field: Unknown.action` + `OOF-TY1 … expected RuleDecision, got Unknown` (exactly 2 diagnostics).
15/16 dual-clean; `rule_engine` the only `oof`.

**Q8. What beyond diagnostics?**
Manifest `entrypoint` (RunDuel/RunAccept/RunConnectedMatched etc.), SemanticIR
stdlib-call `fn` names (the lowered op names must be identical), and stable output
hashes where the fleet baselines already pin them (e.g. the three companion live
hashes from Wave P11).

**Q9. Which surfaces stay closed (so it's not a semantic change)?**
No diagnostic message/code change; no parser/classifier/emitter/assembler/multifile
edit; no app migration; no crate split; no Ruby canon edit; no IO/runtime; no
`cargo fmt` blanket sweep.

**Q10. Mirror Ruby canon `typechecker.rb` now?**
**Defer.** `typechecker.rb` is also large (3435 ln) with the same shape, but it is
**canon** (higher governance bar). Mirror only after the Rust lab seam proves
useful and the parity benefit is concrete; P2 is lab-Rust-only.

---

## 3. Recommended P2

`LAB-RUST-TYPECHECKER-DECOMP-P2` — extract the stdlib call dispatch from
`infer_expr` into `src/typechecker/stdlib_calls.rs`, behavior-preserving.

- Public compiler API unchanged; `infer_expr` becomes a thin router delegating to
  `infer_stdlib_call(...)`.
- Proof matrix: the 16-app fleet, exact diagnostic sets + status + manifest
  entrypoint + SIR stdlib op-names, before/after, via the Open3/mktmpdir subprocess
  route (avoids the package-writer stdout/timing race). `rule_engine` golden (§Q7)
  asserted unchanged. Target ≥ the 60 checks here plus the fleet diff.

**Later modules (named, NOT authorized):** `records.rs` (record-literal +
`structurally_assignable` + `infer_field_expr_type`), `operators.rs`
(`operator_type`), `match_expr.rs` (`infer_match_expr` + future Option/Result
matchability), and finally `infer_expr.rs` once dispatch is out.

---

## 4. Proof

```
runner:  igniter-lab/igniter-compiler/verify_rust_typechecker_decomp_p1.rb
result:  60/60 PASS
sections: A pipeline-modular (7) / B concentration facts (9) / C infer_expr anchors (7) /
          D future-card collision (7) / E stdlib seam safest (7) /
          F P2 matrix + live rule_engine golden (11) / G closed surfaces (7) /
          H future modules + Ruby deferred (5)
```

---

## 5. Closed surfaces (this P1)

No `typechecker.rs` refactor; no behavior/diagnostic change; no parser/emitter/
assembler/classifier/multifile/app edits; no Rust crate/workspace split; no Ruby
canon `typechecker.rb` change; no app migration; no IO/runtime; no `cargo fmt`.

---

## 6. Open routes

| Card | Scope |
|------|-------|
| LAB-RUST-TYPECHECKER-DECOMP-P2 | Extract stdlib dispatch → `typechecker/stdlib_calls.rs`; 16-app behavior-preserving parity proof |
| (later) DECOMP-P3+ | `records.rs` / `operators.rs` / `match_expr.rs` / `infer_expr.rs`, one seam per card |
| (deferred) Ruby canon mirror | Only if the Rust seam proves useful |
