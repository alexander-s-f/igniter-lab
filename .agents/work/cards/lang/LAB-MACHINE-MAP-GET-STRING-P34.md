# LAB-MACHINE-MAP-GET-STRING-P34 - typed string extraction from Map bodies

Status: CLOSED
Lane: language runtime / machine stdlib / TodoApp API unblocker
Type: implementation
Delegation code: OPUS-MACHINE-MAP-GET-STRING-P34
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

P28 proved the important part: `Map[String, Unknown]` values now survive VM/machine runtime and
`stdlib.map.get` can fetch object fields as `Option[Unknown]`.

Todo object body still needs one small typed extraction helper. P25 recommended:

```ig
req.body_json : Map[String, Unknown]
title_opt = stdlib.map.get_string(req.body_json, "title")
```

The previous blocking claim "Map is typechecker-only" is now false after P28. Do not re-litigate
the full Map gate; this card is the narrow typed helper.

## Goal

Add a typed, fail-closed string extractor for map/object bodies:

```text
stdlib.map.get_string(Map[String, Unknown], String) -> Option[String]
```

Use the spelling that matches current stdlib-call conventions. If the codebase prefers bare call
names, support the canonical names consistently and document the accepted surface in the proof.

## Verify first

Read live source before editing:

- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `runtime/igniter-machine/src` Map/Unknown value handling from P28
- `runtime/igniter-machine/tests/map_body_proof_tests.rs`
- any stdlib version/provenance constants touched by package work

Confirm exact current names for `map_get` / `stdlib.map.get` before adding the new helper.

## Required semantics

- present string value -> `Some(value)`
- missing key -> `None`
- present non-string value -> `None`
- null value -> `None`
- no panic, no host diagnostics that echo the body value

This helper is for app-level validation. It should not decide whether missing/non-string is 400;
the Todo handler will decide that in P35.

## Acceptance

- [x] Typechecker accepts `map_get_string` / `stdlib.map.get_string` returning `Option[String]`.
- [x] VM/machine evaluates string/missing/non-string/null cases exactly as specified (6 tests).
- [x] Existing `stdlib.map.get` behavior and P28 tests still pass (5/5).
- [x] A negative typecheck test rejects a non-Map first arg (OOF-TY0 naming `get_string`).
- [x] stdlib version/provenance updated: `STDLIB_VERSION` + `igniter-stdlib/Cargo.toml` `0.1.4→0.1.5` (guard `stdlib_version_mirrors_crate` green); provenance JSON-shape fixtures are version-independent (explained).
- [x] No TodoApp behavior changes in this card.
- [x] `git diff --check` clean.

## Proof

Preferred proof doc:

```text
lab-docs/lang/lab-machine-map-get-string-p34-v0.md
```

Include the exact accepted spelling and a small before/after note from P25/P28.

## Closing report

**Date:** 2026-06-23
**Proof:** [`lab-docs/lang/lab-machine-map-get-string-p34-v0.md`](../../../../lab-docs/lang/lab-machine-map-get-string-p34-v0.md)
**Outcome:** Implemented. Typed, fail-closed `map_get_string` added to the typechecker + VM.

### Accepted spelling

Authored surface: bare `map_get_string(body, "title")` (dotted `stdlib.map.get_string` is the internal
normalized name — does not parse as a callee, same as the rest of the map family). Both accepted.

### Semantics (fail-closed)

`map_get_string(Map[String, Unknown], String) -> Option[String]`: present **String** → `Some(value)`;
missing / present-non-string / `null` → `None`. Option repr matches `map_get` (`None=Nil`, `Some=raw`).
App-level validation only — does not decide 400.

### Changes (smallest layers)

- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`: new arm → `Option[String]`, with negative
  validation (arity 2; arg1 `Map`|`Unknown`; arg2 `String`|`Unknown`; else `OOF-TY0`) mirroring `decimal`.
- `lang/igniter-vm/src/vm.rs`: new `OP_CALL` arm after `map_has_key` — `Record`→`Some` only for a present
  `Value::String`, else `Nil`; single bytecode dispatch site (no eval_ast duplicate).
- `STDLIB_VERSION` `0.1.4→0.1.5` (`igniter-compiler/src/lib.rs`) + `igniter-stdlib/Cargo.toml` `0.1.4→0.1.5`
  (forced by the `stdlib_version_mirrors_crate` guard). `igniter_stdlib::VERSION` is env-derived, so the VM
  experiment provenance now reports stdlib `0.1.5` (correct). The `provenance_json_shape_*` tests feed a
  literal `"0.1.4"` fixture to the JSON builder and assert it echoes back — version-independent, untouched.
- `runtime/igniter-machine/tests/map_get_string_tests.rs`: 6 machine-dispatch tests (string/missing/
  non-string/null/empty + negative typecheck).

### Verification

machine: `map_get_string_tests` 6/6, `map_body_proof_tests` (P28) 5/5. vm: full suite green (rebuilt
against igniter-stdlib 0.1.5). compiler: lib + integration green incl. `stdlib_version_mirrors_crate`. No
TodoApp behavior changed. `git diff --check` clean.

### Next card

`LAB-TODOAPP-API-OBJECT-BODY-Pxx` (app/host): `Request.body_json : Map[String, Unknown]` prelude surface +
`map_get_string(req.body_json, "title")` in the Todo create handler (missing/non-string → 400). Reuses
this helper; no language gate.

## Closed surfaces

- No `Request.body_json` yet.
- No Todo object-body behavior.
- No JSON parser in `.ig`.
- No new product-specific request fields.
