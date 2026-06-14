# LAB-RUST-TYPECHECKER-DECOMP-P2 Proof

**Status:** CLOSED - PROVED 119/119  
**Date:** 2026-06-14  
**Authority:** behavior-preserving Rust lab refactor only

## Summary

P2 extracted the Rust lab typechecker stdlib call dispatch from the inline
`infer_expr` body into `igniter-compiler/src/typechecker/stdlib_calls.rs`.

This is not a semantic card. No stdlib behavior, OOF code, parser surface,
emitter behavior, app source, runtime, IO, or Ruby canon surface was intentionally
changed.

## Implementation

Changed implementation files:

- `igniter-compiler/src/typechecker.rs`
- `igniter-compiler/src/typechecker/stdlib_calls.rs`

Shape after extraction:

| Source | Lines |
|---|---:|
| `typechecker.rs` | 4520 |
| `typechecker/stdlib_calls.rs` | 1379 |
| `infer_expr` | 626 |

The module is declared from `typechecker.rs` with:

```rust
#[path = "typechecker/stdlib_calls.rs"]
mod stdlib_calls;
```

`infer_expr` still infers args, resolves user-defined functions first, then calls
`infer_stdlib_call(...)` only when the function is not already resolved. Unknown
function fallback remains in `infer_expr`.

## Proof

Runner:

```text
igniter-compiler/verify_rust_typechecker_decomp_p2.rb
```

Result:

```text
119/119 PASS
```

Proof sections:

- Source shape: nested module present, no `typechecker/mod.rs`, stdlib arms moved.
- Build: `cargo build --release` succeeds.
- P1 fixed-state verifier: `verify_rust_typechecker_decomp_p1.rb` passes 60/60.
- Wave P11 Rust matrix: all 16 apps compile with expected statuses.
- `rule_engine` golden: exact fail-closed diagnostics unchanged.
- Companion entrypoints: `RunDuel`, `RunAccept`, `RunConnectedMatched` unchanged.
- Representative SemanticIR stdlib names: string, collection, and fold lowering
  paths remain present.
- Closed surfaces: no app, parser, emitter, assembler, classifier, multifile, or
  Ruby canon edits.

## Wave P11 Matrix

| App group | Result |
|---|---|
| 15 clean apps | `ok/0` |
| `rule_engine` | `oof/2` |

Exact `rule_engine` diagnostics:

| Rule | Message | Node |
|---|---|---|
| `OOF-P1` | `Unresolved field: Unknown.action` | `active_decisions` |
| `OOF-TY1` | `Output type mismatch: expected RuleDecision, got Unknown` | `decision` |

## Entrypoint Parity

| App | Entrypoint |
|---|---|
| `air_combat` | `RunDuel` |
| `lead_router` | `RunAccept` |
| `call_router` | `RunConnectedMatched` |

## Representative SemanticIR Checks

Observed unchanged paths include:

- `stdlib.string.char_at`
- `stdlib.string.substring`
- `stdlib.collection.append`
- `stdlib.collection.map`
- `stdlib.collection.filter`
- `stdlib.collection.count`
- `stdlib.collection.concat`
- fold lowering path (`kind: fold`)

## Closed Surfaces

- No semantic changes.
- No new stdlib functions.
- No OOF code, message, or node changes.
- No parser, lexer, classifier, emitter, assembler, multifile, monomorphizer, or
  liveness edits.
- No app source edits.
- No Ruby canon mirror.
- No crate/workspace split.
- No `cargo fmt` sweep.
- No IO/runtime work.

## Verdict

P2 is closed. The first Rust typechecker decomposition seam is implemented and
proved behavior-preserving against the Wave P11 fleet.
