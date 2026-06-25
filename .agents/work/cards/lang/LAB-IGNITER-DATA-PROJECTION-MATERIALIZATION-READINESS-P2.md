# LAB-IGNITER-DATA-PROJECTION-MATERIALIZATION-READINESS-P2

Status: CLOSED (feasibility packet delivered 2026-06-25)
Route: standard / deep readiness
Skill: idd-agent-protocol

## Closing report (2026-06-25)

Packet: `lab-docs/lang/lab-igniter-data-projection-materialization-readiness-p2-v0.md`.

**Feasibility verdict: `small-gap`.** The VM value substrate is already capable; the gap is host-side only.

**Exact live materialization path (verified):**
- `lang/igniter-vm/src/value.rs:7-16` — `Value` has **no `Map` variant**; JSON objects and `Map[String,
  Unknown]` are *both* `Value::Record` at runtime.
- `value.rs:51-99` — `from_json`: array → `Value::Array`, object → `Value::Record`. So a serde
  **array-of-objects → `Collection[Record]`** with no extra machinery.
- `runtime/igniter-machine/src/machine.rs:327-330` — `dispatch` materializes each top-level input via
  `from_json`, **type-erased** (never consults the declared input type). The declared `Collection[TodoRow]`
  matters only at compile time → **no type-directed materializer to build.**
- `server/igniter-web/src/read_dispatch.rs:111` — the host **stringifies** already-typed rows
  (`serde_json::to_string(outcome.result["rows"])`); `lib.rs:120` crosses that string as `rows_json`. The
  single thing between here and `Collection[Record]` is that `to_string`.

**`Collection[Record]` crossing already possible?** Yes at the substrate; the two halves are proven live
(consumption: `query_engine` green, `input rows : Collection[Row]` + `row.age`/`filter`/`fold`,
`IMPLEMENTED_SURFACE.md:147-152`; host-JSON→Record: `req.body_json`). Only their *join in one read path* is
unexercised — that is the implementation card.

**Mismatch ownership.** Field-access missing-field behavior is **path-dependent** (error in `OP_GET_FIELD`
`vm.rs:2762` & general `field_access` `vm.rs:3912`; whole-record passthrough in the ref fast-path
`vm.rs:3887`; `Nil` in HOF-inlined accessors `vm.rs:2667`,…). So the stable error surface must be
**host-owned**: a `materialize_rows(rows, spec)` reshape validates totality/NULL/kind before crossing and
surfaces the read-gate taxonomy, leaving `.ig` rows total + typed. Decimal/Timestamp cross as `String` in v0
(typed-Decimal has a runtime landing pad at `value.rs:82-91`).

**Why this avoids JSON-string/decoder DX:** rows arrive as native `Value::Record`s accessed by
`r.field`/`map`/`filter` directly — no in-language JSON parser, no per-field `map_get_string`, no app-side
decoder for host-owned relational reads.

**Smallest implementation card:** `LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6` — host materializer +
typed continuation, fake-adapter DB-free harness, host-owned mismatch taxonomy (packet §7).

**Boundary honored.** No production code / test fixture / `.igweb` / compiler / VM / Postgres / Todo change;
no "implemented" claim; no canon claim. Docs only (packet + this report). `git diff --check` clean; grep →
`/tmp/igniter-materialization-grep.txt` (2230 hits).

## Goal

Answer the hardest technical question left by P1:

> Can host-held typed row values cross into a `.ig` continuation as
> `Collection[AppRow]`, so `r.title`, `r.done`, `filter`, `map`, and
> `call_contract` work as typed record operations?

This is **research only**. Do not implement the crossing. Produce a precise feasibility packet and the
smallest implementation plan.

## Current Authority

- P1 packet: `lab-docs/lang/lab-igniter-data-projection-boundary-readiness-p1-v0.md`.
- Live VM/compiler source decides actual feasibility.
- Old proof docs are evidence only.

## Verify First

Read live code, not assumptions:

- `server/igniter-web/src/lib.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `runtime/igniter-machine/src/postgres_read.rs`
- `lang/igniter-vm/src/vm.rs`
- `lang/igniter-vm/src/value.rs` or equivalent value representation files
- `lang/igniter-compiler/src/typechecker*`
- any `from_json` / `to_json` / `serde_json::Value` conversion paths
- fleet precedents:
  - `apps/igniter-apps/query_engine/`
  - `apps/igniter-apps/batch_importer/`
  - `server/igniter-web/examples/todo_view_app/`

## Questions To Answer

1. Where exactly does JSON/serde input become VM values today?
   - file/function names;
   - how objects become records or maps;
   - how arrays become `Collection`.
2. Does the machine already know a contract's input type at dispatch time?
   - Can the host ask "continuation expects `Collection[TodoRow]`"?
   - Or is input materialization type-erased?
3. Is `serde_json::Value::Array(Object...)` enough to become `Collection[Record]`?
   - If yes, cite the code path.
   - If no, name the exact missing adapter.
4. What happens on:
   - missing field;
   - extra field;
   - wrong scalar kind (`Bool` expected, string supplied);
   - `null` for non-nullable field;
   - integer/decimal/text precision boundaries?
5. Can `Collection[TodoRow]` values produced by the host be used inside HOFs?
   - `filter(rows, r -> r.done == false)`
   - `map(rows, r -> r.title)`
   - `map(rows, r -> call_contract("TodoLabel", r))`
6. Is the failure surface host-owned or VM-owned today?
   - What would make an error stable enough for P3?

## Design Bias

Prefer proving the existing VM/value machinery can do this with a small typed materializer. Avoid:

- adding JSON parser DX to `.ig`;
- making app code use `Map[String, Unknown]` for normal relational reads;
- inventing a new language feature before proving the current value substrate cannot carry rows.

## Boundary

Allowed:

- Write a readiness packet in `lab-docs/lang/`.
- Run grep and existing tests.
- Create temporary scratch files outside the repo if needed, but do not commit them.
- Include pseudo-code / implementation sketch.

Closed:

- No production code changes.
- No test fixture committed.
- No `.igweb`, compiler, VM, Postgres, or Todo app implementation.
- No claim that typed row crossing is implemented.
- No canon claim.

## Required Packet

Create:

`lab-docs/lang/lab-igniter-data-projection-materialization-readiness-p2-v0.md`

Must include:

- exact live value materialization path;
- feasibility verdict: `ready`, `small-gap`, or `blocked`;
- exact missing gap if any;
- proposed host materializer shape;
- mismatch/error behavior recommendation;
- smallest implementation card with acceptance tests.

## Verification

Run at minimum:

```bash
rg -n "from_json|to_json|serde_json|Value::Record|Value::Map|Collection|dispatch\\(" \
  lang/igniter-vm lang/igniter-compiler server/igniter-web runtime/igniter-machine \
  > /tmp/igniter-materialization-grep.txt

git diff --check
```

If you run any scratch experiment, describe it and keep it out of git.

## Acceptance

- [x] Packet exists at the required path.
- [x] It cites the exact live materialization code path.
- [x] It answers whether `Collection[Record]` crossing is already possible.
- [x] It names all mismatch cases and who should own them.
- [x] It gives a concrete smallest implementation card.
- [x] No code/test/source files changed.
- [x] `git diff --check` clean.

## Reporting

Close with:

- feasibility verdict;
- exact implementation gap;
- why this avoids JSON-string/decoder DX;
- next implementation card.
