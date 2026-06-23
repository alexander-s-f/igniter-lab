# LAB-MACHINE-MAP-GET-STRING-P34 — proof

**Date:** 2026-06-23
**Type:** implementation (narrow typed stdlib helper)
**Outcome:** `map_get_string` added to the typechecker + VM; fail-closed; proven through `IgniterMachine`.

## Before / after (P25 → P28 → P34)

- **P25** (readiness) wrongly claimed the Map runtime was missing → it recommended an object body but
  said it was blocked on a VM/Map gate.
- **P28** proved the Map runtime gate is **already live** (`Value::Record` Map, `map_get`/`map_has_key`
  through machine dispatch). It surfaced the one real friction: `map_get` returns `Option[Unknown]`, so a
  `String`-typed output needs a typed coercion.
- **P34** (this card) closes exactly that friction with a typed, fail-closed extractor — no Map re-litigation.

## Accepted spelling

Authored `.ig` surface is the **bare name**: `map_get_string(body, "title")`. The dotted form
`stdlib.map.get_string(...)` is the internal normalized name (it does not parse as a callee — same as the
rest of the map family). Both spellings are accepted by the typechecker and VM handlers.

## Semantics (fail-closed)

`map_get_string(Map[String, Unknown], String) -> Option[String]`

| Map value at key | Result |
| --- | --- |
| present **String** | `Some(value)` (raw string) |
| missing key | `None` |
| present **non-string** (number/bool/object/array) | `None` |
| `null` | `None` |

Option representation matches `map_get`: `None = Value::Nil`, `Some(v) = raw v`. No host diagnostic
echoes the body value. This helper is for **app-level validation only** — it does not decide 400; the Todo
handler will (a later card).

## Implementation (smallest layers)

- **Typechecker** (`lang/igniter-compiler/src/typechecker/stdlib_calls.rs`): new arm
  `"map_get_string" | "stdlib.map.get_string"` → resolves to `Option[String]` unconditionally (the typed
  contract), and **validates args** (negative typecheck, mirrors the `decimal` precedent): arity must be 2;
  arg 1 must be `Map` or `Unknown`; arg 2 must be `String` or `Unknown` — otherwise `OOF-TY0`. `Unknown` is
  allowed so a dynamic `req.body_json` input still type-resolves.
- **VM** (`lang/igniter-vm/src/vm.rs`): new `OP_CALL` arm after `map_has_key` — `Value::Record` → `Some`
  only when `map.get(key)` is `Value::String`, else `Value::Nil`; `Value::Nil` map → `Nil`; any other
  first arg → runtime error (matches `map_get`'s guard). Single bytecode dispatch site (no eval_ast
  duplicate — `map_get`/`map_has_key` have only this site).
- **stdlib version/provenance**: `map_get_string` is a new baked-in `stdlib.*` signature, so
  `STDLIB_VERSION` bumped `0.1.4 → 0.1.5` (`lang/igniter-compiler/src/lib.rs`), and — required by the
  `stdlib_version_mirrors_crate` guard — `igniter-stdlib/Cargo.toml` `0.1.4 → 0.1.5`. `igniter_stdlib::VERSION`
  is `env!("CARGO_PKG_VERSION")`, so the VM experiment provenance now reports stdlib `0.1.5` (correct — the
  surface grew). The `provenance_json_shape_*` tests pass a literal `"0.1.4"` fixture to the JSON builder
  and assert it echoes back; they are version-independent and unaffected (left untouched, out of scope).

## Proof

`runtime/igniter-machine/tests/map_get_string_tests.rs` (6 tests, all green) — dispatches
`map_get_string(body, "title")` through `IgniterMachine`:

- present string → `"Buy milk"` (body also carries nested/non-string fields → no panic);
- missing key → `None` (observed via `or_else(.., "<<none>>")`);
- present non-string (number/bool/object/array) → `None`;
- `null` → `None`;
- empty map → `None`;
- **negative typecheck**: a contract calling `map_get_string(n, "title")` with `n : Integer` fails
  `load_contract_source` with an `OOF-TY0` naming `get_string`.

## Verification

- `runtime/igniter-machine` `map_get_string_tests` 6/6; P28 `map_body_proof_tests` 5/5 (existing `map_get`
  behavior intact).
- `lang/igniter-vm` full suite green (rebuilt against igniter-stdlib 0.1.5).
- `lang/igniter-compiler` lib + integration suites green, incl. `stdlib_version_mirrors_crate`.
- No TodoApp behavior changed. `git diff --check` clean.

## Next card

`LAB-TODOAPP-API-OBJECT-BODY-Pxx` (app/host): add a `Request.body_json : Map[String, Unknown]` prelude
surface + use `map_get_string(req.body_json, "title")` in the Todo create handler to accept
`{ "title": "Buy milk" }`, deciding missing/non-string → 400. Reuses this helper; no language gate.
