# LAB-MACHINE-MAP-VALUE-AND-STDLIB-GET-P28 - live Map runtime gate for object request bodies

Status: CLOSED
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

- [x] Live Map runtime state reconciled against `LAB-MAP-RUST-P1`, `LAB-VM-MAP-P1`, and P25.
- [x] No duplicate `Value::Map` is introduced — `Value::Record(Arc<BTreeMap<String,Value>>)` is the live repr; no code added.
- [x] `IgniterMachine::dispatch` proof passes with a JSON object input crossing into a Map-like value.
- [x] `stdlib.map.get` returns present value and fallback on missing key.
- [x] `stdlib.map.has_key` returns correct Bool.
- [x] Non-string/nested values are characterized; no panic, no host authority leak.
- [x] If code changed: N/A — no code changed (the "already live" branch).
- [x] If code did not need changes: closing report states "already live" with file/line evidence and proof test.
- [x] P25 stale statement corrected in a minimal doc patch (3 spots, marked `[CORRECTED by P28]`).
- [x] `cargo test` for the proof passes (`map_body_proof_tests` 5/5). NOTE: igniter-machine has 2 **pre-existing, unrelated** failures (`test_machine_loads_multifile_app` record-literal parse, `test_machine_fleet_sweep` `variant_construct` VM gap) — `machine_tests.rs` contains zero map references; not introduced or affected by this card.
- [x] `git diff --check` clean.

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

## Closing report

**Date:** 2026-06-23
**Outcome:** Gate **ALREADY LIVE** — no production source code changed. Proof test + minimal P25
correction; `runtime/igniter-machine/Cargo.lock` refreshed to the already-live `igniter_stdlib 0.1.4`
/ `libm` dependency state.

### Finding: the Map runtime gate is live (P25's "blocked" claim was wrong)

Verify-first against live source (not stale prose) confirmed every piece exists:

- **VM Map representation:** `lang/igniter-vm/src/value.rs:15` — `Value::Record(Arc<BTreeMap<String,Value>>)`
  is the Map repr (there is **no separate `Value::Map`**); `Value::from_json` (value.rs:51, 92-96) crosses
  a JSON object into `Value::Record`.
- **VM eval handlers:** `lang/igniter-vm/src/vm.rs:2656` `"map_get" | "stdlib.map.get"` and `vm.rs:2675`
  `"map_has_key" | "stdlib.map.has_key"`, both requiring a `Record` first arg (`map_get` → raw value if
  present, `Nil` if absent).
- **Typechecker signatures:** `lang/igniter-compiler/src/typechecker/stdlib_calls.rs:2467+`
  (`stdlib.map.get(Map[String,V],String) → Option[V]`, `has_key → Bool`), tagged LAB-MAP-RUST-P1.
- **Machine crossing:** `runtime/igniter-machine/src/machine.rs::dispatch` populates VM inputs from the
  serde object, so a JSON-object input binds to a `Map[String, Unknown]` contract input.

### Proof

`runtime/igniter-machine/tests/map_body_proof_tests.rs` (NEW, 5 tests, all green) dispatches two pure
contracts (`TitleFromBody`, `HasTitle`) over a `Map[String, Unknown]` input **through `IgniterMachine`**:
present title → `"Buy milk"`; missing → fallback `""`; `has_key` true/false; a body with nested/non-string
values (`done:false`, `n:1`) does not panic; result serializes to clean JSON.

### Two findings surfaced while writing the proof

1. **Authored surface is the BARE name.** `.ig` must call `map_get(body, "title")` / `map_has_key(...)`;
   the dotted `stdlib.map.get(...)` form does NOT parse as a callee (`OOF-P0` at the `(`). The dotted form
   is the internal normalized name only. (Documented in the test header.)
2. **Ergonomics gap (not a runtime gap):** `map_get` returns `Option[Unknown]`, so `or_else(.., "")` is
   `Unknown` and a `String`-typed output is rejected (`OOF-TY1: expected String, got Unknown`). The proof
   uses an `Unknown` output. A typed-`String` extraction (to reject a non-string title) needs either a
   small `map_get_string` helper or a host body-field shape signal — **deferred to the Todo object-body
   card**, NOT implemented speculatively here (per the card's optional-helper guidance).

### P25 correction (minimal doc patch)

`lab-docs/lang/lab-todoapp-api-create-object-body-readiness-p25-v0.md` carried the stale claim "the VM has
no `Value::Map` and no `stdlib.map.get` evaluation" (its grep was for `stdlib.map.*` and missed the
bare-name handlers). Corrected in 3 spots marked `[CORRECTED by P28]`: the intro, the live-constraints
bullet, and the conclusion — the object-body path is **not** blocked on a language/VM card; only an
app/host `Option[Unknown]`→`String` decision remains.

### Next implementation card (redirect)

The Todo object-body work (was framed as blocked on this gate) is now an **app/host** card, not a language
one: add a `Request.body_json : Map[String, Unknown]` prelude surface + decide the `Unknown`→`String`
coercion (typed `map_get_string` helper that fails closed on non-string, or reuse a P18-style `body_kind`
shape signal per field). Scope: `igniter-compiler` prelude + `igniter-web` body crossing + the Todo create
handler; reuses the now-proven Map runtime.

### Verification

`cargo test --test map_body_proof_tests` → 5/5 green. `git diff --check` clean. No production source code
changed (new proof test + 3-spot doc correction; lockfile refresh only). The 2 pre-existing
`machine_tests` failures (record-literal multifile parse, `variant_construct` VM gap) are unrelated
frontier gaps — `machine_tests.rs` has zero map references — and are not in this card's scope.

## Closed surfaces

- No Todo API behavior change in this card.
- No `Request.body_json` prelude field in this card unless verify-first proves the Map runtime gate is already
  live and the agent explicitly chooses to split a tiny follow-up instead of patching here.
- No JSON parser stdlib in this card.
- No non-string Map keys.
- No map mutation (`set`, `delete`) and no broad collection redesign.
- No public/canon claim.
