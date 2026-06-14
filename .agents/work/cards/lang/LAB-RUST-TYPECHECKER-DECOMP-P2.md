# LAB-RUST-TYPECHECKER-DECOMP-P2

**Status:** CLOSED — PROVED 119/119  
**Route:** lab / compiler hygiene / Rust typechecker decomposition implementation  
**Date:** 2026-06-14  
**Authority:** behavior-preserving Rust lab refactor only

## Goal

Implement the first Rust typechecker decomposition seam proven by
`LAB-RUST-TYPECHECKER-DECOMP-P1`: extract stdlib call dispatch out of the giant
`infer_expr` body while preserving behavior exactly.

P2 is not a semantic card. It is a refactor card. The proof must show that every
observable compile result and diagnostic shape stays the same.

## Gate

Start only after:

- `LAB-RUST-TYPECHECKER-DECOMP-P1` CLOSED — READINESS PROVED 60/60.
- `APP-RECHECK-WAVE-P11` CLOSED — 15/16 DUAL-CLEAN; `rule_engine` is the only
  intentional blocked app.

P1 measured facts to preserve as context:

| Fact | Value |
|---|---:|
| `typechecker.rs` | 5849 lines |
| `infer_expr` | 1958 lines, lines ~2679–4637 |
| `typecheck_contract` | 877 lines |
| stdlib dispatch arms in `infer_expr` | large contiguous hotspot, incl. `substring`, `first`/`last`, `map`, `fold` |
| pass modules in `lib.rs` | 11 — pipeline already modular |

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-RUST-TYPECHECKER-DECOMP-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-rust-typechecker-decomp-p1-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/verify_rust_typechecker_decomp_p1.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/app-pressure-recheck-wave-p11-2026-06-14-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/APP-RECHECK-WAVE-P11.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/lib.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/typechecker.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/emitter.rs`

## Implementation Scope

Allowed changes:

- `igniter-compiler/src/typechecker.rs`
- one new Rust module file for stdlib call dispatch, recommended:
  `igniter-compiler/src/typechecker/stdlib_calls.rs`
- one proof runner:
  `igniter-compiler/verify_rust_typechecker_decomp_p2.rb`
- proof doc:
  `lab-docs/lang/lab-rust-typechecker-decomp-p2-proof-v0.md`
- this card closure + portfolio update

Important implementation note:

Rust cannot have both `src/typechecker.rs` and `src/typechecker/mod.rs` for the
same module. Do **not** convert the whole file to `typechecker/mod.rs` in P2.
Instead, use a nested submodule from inside `typechecker.rs`, for example:

```rust
#[path = "typechecker/stdlib_calls.rs"]
mod stdlib_calls;
```

Then move only the stdlib-call handling code behind a helper such as
`infer_stdlib_call(...)`, keeping `TypeChecker` public API unchanged.

The exact helper signature is agent-chosen, but it must preserve ownership and
diagnostic behavior. Prefer a small internal result enum over ad hoc sentinel
strings if it makes the router clearer.

## Expected Extraction Shape

`infer_expr` should become thinner around `Expr::Call` / call dispatch:

1. Infer typed args exactly as before.
2. Ask the stdlib-dispatch helper whether `fn_name` is a known stdlib call.
3. If handled, return the exact same typed expression + type info as before.
4. If not handled, continue with existing user-contract / call_contract / unknown
   function handling exactly as before.

Stdlib dispatch candidates include, but are not limited to:

- string/text surfaces: `substring`, `char_at`, `split`, `contains`, etc. where
  currently present.
- collection surfaces: `first`, `last`, `map`, `filter`, `flat_map`, `fold`,
  `range`, `append`, `concat`, `count`, `sum`, `avg`, `is_empty`, `non_empty`, etc.
- numeric/string helper arms already located in the stdlib call block.

Do not invent new stdlib behavior and do not normalize unrelated call paths.

## Proof Requirements

P2 proof must be stronger than “cargo build passes”. It must include:

1. Baseline capture before refactor or an embedded golden matrix from P1/Wave P11.
2. Rust build succeeds after refactor.
3. `verify_rust_typechecker_decomp_p1.rb` still passes or is updated only from
   pre-refactor assertions to fixed-state assertions.
4. Full 16-app Wave P11 Rust compile matrix via Open3/mktmpdir/fresh `--out`.
5. Exact status parity for all 16 apps.
6. Exact diagnostic `{rule, message, node}` parity for all non-clean apps.
7. Exact `rule_engine` golden trace unchanged:
   - `OOF-P1` with `Unresolved field: Unknown.action` at `active_decisions`.
   - `OOF-TY1` with `expected RuleDecision, got Unknown` at `decision`.
8. DUAL-CLEAN apps remain clean: the 15 non-`rule_engine` apps produce `ok/0`.
9. Manifest entrypoint parity for companion apps:
   - `air_combat` → `RunDuel`
   - `lead_router` → `RunAccept`
   - `call_router` → `RunConnectedMatched`
10. Representative SemanticIR stdlib call names remain unchanged for at least:
    - `stdlib.collection.fold` / fold lowering path if present in output
    - `stdlib.collection.map`
    - `stdlib.collection.filter`
    - `stdlib.string.substring` or current canonical string fn name
    - `stdlib.collection.first` / `last` if current compiler emits them
11. `typechecker.rs` no longer contains the full stdlib dispatch body inline; the
    new module contains the moved dispatch code.
12. No edits outside allowed files, except generated proof/doc/card/portfolio.

Proof runner target: **at least 80 checks**.

## Acceptance

- `cargo build` or equivalent Rust compiler build succeeds.
- The 16-app Rust compile matrix has identical statuses to Wave P11:
  - 15 apps `ok/0`.
  - `rule_engine` `oof/2` with exact golden diagnostics.
- No diagnostic codes/messages/nodes change.
- No app source changes.
- No parser/emitter/assembler/classifier/multifile changes.
- No Rust crate/workspace split.
- No Ruby canon changes.
- No `cargo fmt` blanket sweep.
- `infer_expr` is measurably smaller, and stdlib dispatch is hosted in the new
  module.
- P1 proof still passes or is deliberately updated to fixed-state source checks.

## Deliverables

- Implementation: `igniter-compiler/src/typechecker.rs` + new stdlib dispatch
  module.
- Proof runner:
  `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/verify_rust_typechecker_decomp_p2.rb`.
- Proof doc:
  `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-rust-typechecker-decomp-p2-proof-v0.md`.
- Update this card with closure summary.
- Portfolio index update after closure.

## Closed Surfaces

- No semantic changes.
- No new stdlib functions.
- No OOF code/message changes.
- No parser, lexer, classifier, emitter, assembler, multifile, monomorphizer,
  liveness, or app source edits.
- No Ruby canon mirror.
- No crate/workspace split.
- No broad formatting sweep.
- No IO/runtime work.
- No app migrations.

## Closure Summary (2026-06-14)

**Status:** CLOSED — PROVED.

P2 implemented the behavior-preserving Rust lab refactor selected by P1:
stdlib call dispatch is now hosted in
`igniter-compiler/src/typechecker/stdlib_calls.rs`, while
`igniter-compiler/src/typechecker.rs` keeps the `TypeChecker` public API and
`infer_expr` call flow unchanged.

Measured fixed-state shape:

| Fact | Value |
|---|---:|
| `typechecker.rs` | 4520 lines |
| `typechecker/stdlib_calls.rs` | 1379 lines |
| `infer_expr` | 626 lines |

Proof:

- `cargo build --release` succeeds.
- `verify_rust_typechecker_decomp_p1.rb` updated to fixed-state source checks:
  **60/60 PASS**.
- `verify_rust_typechecker_decomp_p2.rb`: **119/119 PASS**.
- Wave P11 Rust matrix preserved exactly:
  - 15 apps `ok/0`.
  - `rule_engine` `oof/2`.
- Exact `rule_engine` golden unchanged:
  - `OOF-P1` / `Unresolved field: Unknown.action` / `active_decisions`.
  - `OOF-TY1` / `Output type mismatch: expected RuleDecision, got Unknown` /
    `decision`.
- Manifest entrypoints unchanged:
  - `air_combat` -> `RunDuel`.
  - `lead_router` -> `RunAccept`.
  - `call_router` -> `RunConnectedMatched`.
- Representative SemanticIR names/path checks preserved:
  `stdlib.string.char_at`, `stdlib.string.substring`,
  `stdlib.collection.append`, `stdlib.collection.map`,
  `stdlib.collection.filter`, `stdlib.collection.count`,
  `stdlib.collection.concat`, and fold lowering path.

Closed surfaces preserved: no semantic changes, no new stdlib functions, no OOF
code/message/node changes, no app source changes, no parser/emitter/assembler/
classifier/multifile/monomorphizer/liveness edits, no Ruby canon mirror, no
crate/workspace split, no `cargo fmt` sweep, no IO/runtime work.

Deliverables:

- Implementation: `igniter-compiler/src/typechecker.rs` and
  `igniter-compiler/src/typechecker/stdlib_calls.rs`.
- Proof runner: `igniter-compiler/verify_rust_typechecker_decomp_p2.rb`.
- Proof doc: `lab-docs/lang/lab-rust-typechecker-decomp-p2-proof-v0.md`.

## Agent Recommendation

Best agent: **Codex GPT 5.5**.

Why: P1 already did the deep seam analysis. P2 is now a controlled mechanical
extraction with a strict proof matrix. Codex should be good at incremental edits,
compile failures, borrow-checker repair, and proof-runner iteration.

Good fallback: **Claude Sonnet 4.6**, especially if Codex capacity is needed for
parallel app/governance work.

Use **Claude Opus 4.8** only if the extraction reveals an unexpected ownership
problem or if the agent concludes the P1 seam is wrong. Do not spend Opus on the
happy-path mechanical extraction.

Avoid assigning Gemini as the first implementer for P2 unless a Codex/Sonnet
review is scheduled, because the risk is subtle diagnostic drift rather than raw
code generation.
