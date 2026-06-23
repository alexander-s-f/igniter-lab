# LAB-MACHINE-MAP-GET-STRING-P34 - typed string extraction from Map bodies

Status: TODO
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

- [ ] Typechecker accepts `stdlib.map.get_string(map, key)` returning `Option[String]`.
- [ ] VM/machine evaluates string/missing/non-string/null cases exactly as specified.
- [ ] Existing `stdlib.map.get` behavior and P28 tests still pass.
- [ ] A negative typecheck test rejects non-Map first arg or non-String key.
- [ ] If stdlib version/provenance is tracked for this surface, it is updated or the proof explains why not.
- [ ] No TodoApp behavior changes in this card.
- [ ] `git diff --check` clean.

## Proof

Preferred proof doc:

```text
lab-docs/lang/lab-machine-map-get-string-p34-v0.md
```

Include the exact accepted spelling and a small before/after note from P25/P28.

## Closed surfaces

- No `Request.body_json` yet.
- No Todo object-body behavior.
- No JSON parser in `.ig`.
- No new product-specific request fields.
