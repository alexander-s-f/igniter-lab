# LAB-MACHINE-MAP-VALUE-AND-STDLIB-GET-P28 - live Map runtime gate for object request bodies

Status: TODO
Lane: language-runtime / machine / app-pressure
Type: verify-first implementation or proof-redirect
Delegation code: OPUS-MACHINE-MAP-VALUE-STDLIB-GET-P28
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

`LAB-TODOAPP-API-CREATE-OBJECT-BODY-READINESS-P25` recommends moving Todo create from the awkward v0:

```text
body: "Buy milk"
```

to the real API shape:

```json
{ "title": "Buy milk" }
```

via a generic host/body surface:

```ig
req.body_json : Map[String, Unknown]
stdlib.map.get(req.body_json, "title")
```

P25's wording says this is blocked on `Value::Map` / `stdlib.map.get` VM support. However, live archaeology
shows older lab work that may already cover most or all of that:

- `LAB-MAP-RUST-P1` — typechecker support for `Map[String,V]` and `stdlib.map.get`.
- `LAB-VM-MAP-P1` — VM runtime support using `Value::Record(BTreeMap<String, Value>)` as the Map
  representation; `map_get` / `map_has_key` handlers.
- current `lang/igniter-vm/src/value.rs` already maps JSON objects to `Value::Record` in `Value::from_json`.
- current `runtime/igniter-machine/src/machine.rs` dispatch crosses `serde_json::Value` inputs through
  `VMValue::from_json`.

So this card is **not** "blindly add a new Map type". It is a verify-first reconciliation card.

## Goal

Determine whether the current machine dispatch path can already execute:

```ig
pure contract TitleFromBody(body : Map[String, Unknown]) -> ...
  title = stdlib.map.get(body, "title")
```

from a JSON object input, and close the exact remaining gap.

Expected outcomes:

1. **If live path already works:** add a focused machine/compiler proof and close this as "gate already
   live"; update stale wording in P25 proof doc or closing report only if authorized by scope; name the
   next Todo implementation card.
2. **If there is a real gap:** patch the smallest layer only (likely VM eval alias, machine input crossing,
   or missing typed helper), then add the same proof.

## Verify first

Read these before editing:

- `.agents/work/cards/lang/LAB-MAP-RUST-P1.md`
- `.agents/work/cards/lang/LAB-VM-MAP-P1.md`
- `lab-docs/lang/lab-todoapp-api-create-object-body-readiness-p25-v0.md`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-vm/src/value.rs`
- `lang/igniter-vm/src/vm.rs`
- `runtime/igniter-machine/src/machine.rs`
- any current tests mentioning `map_get`, `stdlib.map.get`, `Map[String`, `or_else`.

Live source wins over stale proof prose. If a doc says "VM has no map_get" but source proves otherwise,
the doc is stale evidence, not authority.

## Required proof

Add a small fixture/test that dispatches through `IgniterMachine`, not only through a direct VM helper:

```ig
module MapBodyProof

type BodyMap = Map[String, Unknown]

pure contract TitleFromBody {
  input body : BodyMap
  compute maybe_title = stdlib.map.get(body, "title")
  compute title = or_else(maybe_title, "")
  output title : String
}

pure contract HasTitle {
  input body : BodyMap
  compute present = stdlib.map.has_key(body, "title")
  output present : Bool
}
```

Drive with JSON inputs equivalent to:

```json
{ "body": { "title": "Buy milk", "done": false, "n": 1 } }
```

Acceptance should prove:

- present string title returns `"Buy milk"`;
- missing title returns fallback `""`;
- `has_key` true/false works;
- nested/non-string values do not panic or leak authority;
- machine dispatch serializes the result back to clean JSON.

If the typechecker rejects `Map[String, Unknown]` as an input/output annotation, record the exact OOF code
and patch only if the fix is local to already-proven Map support.

## Optional helper

If the proof reveals that `stdlib.map.get` returns `Option[Unknown]` and app ergonomics need a typed string
filter, evaluate a tiny helper:

```ig
stdlib.map.get_string(Map[String, Unknown], String) -> Option[String]
```

Do **not** implement it speculatively. Only add it if the proof shows there is no clean way to reject a
non-string title in `.ig` for the Todo body matrix. If added, it must fail closed on non-string values and
include typechecker + VM tests.

## Acceptance

- [ ] Live Map runtime state reconciled against `LAB-MAP-RUST-P1`, `LAB-VM-MAP-P1`, and P25.
- [ ] No duplicate `Value::Map` is introduced if `Value::Record` is already the live Map representation.
- [ ] `IgniterMachine::dispatch` proof passes with a JSON object input crossing into a Map-like value.
- [ ] `stdlib.map.get` returns present value and `Nil`/fallback on missing key.
- [ ] `stdlib.map.has_key` returns correct Bool.
- [ ] Non-string/nested values are characterized; no panic, no host authority leak.
- [ ] If code changed: focused tests cover typechecker + VM/machine path.
- [ ] If code did not need changes: closing report states "already live" with file/line evidence and proof test.
- [ ] P25 stale statement is either corrected in a minimal doc patch or explicitly called out in the closing report.
- [ ] `cargo test` for the touched crate(s) passes.
- [ ] `git diff --check` clean.

## Deliverable

If code changes are needed:

- production/lab source patch in the smallest relevant crate;
- proof test fixture;
- closing report in this card.

If no code changes are needed:

- proof test only, plus closing report explaining the redirect to Todo object body implementation.

Preferred proof doc only if the result is non-obvious:

```text
lab-docs/lang/lab-machine-map-value-and-stdlib-get-p28-v0.md
```

## Closed surfaces

- No Todo API behavior change in this card.
- No `Request.body_json` prelude field in this card unless verify-first proves the Map runtime gate is already
  live and the agent explicitly chooses to split a tiny follow-up instead of patching here.
- No JSON parser stdlib in this card.
- No non-string Map keys.
- No map mutation (`set`, `delete`) and no broad collection redesign.
- No public/canon claim.

