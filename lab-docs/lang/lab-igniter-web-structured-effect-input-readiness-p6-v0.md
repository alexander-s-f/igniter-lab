# lab-igniter-web-structured-effect-input-readiness-p6-v0 — structured write intent across InvokeEffect

**Card:** `LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-READINESS-P6` · **Delegation:**
`OPUS-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-P6`
**Status:** CLOSED (readiness/design — **no implementation**). Recommends **Alternative A**: re-type
`InvokeEffect.input` from `String` to a VM-serialized **structured record** carried through as
`serde_json::Value`, reusing the proven `RespondView`/`RenderView` record-pass-through path. Authority stays
host-side; the app names only logical `target` + structured `values`. No canon claim.
**Authority:** Lab tooling design (effect-host seam).

## Live current protocol shape (verified)

The seam is **narrower than the blocker suggests** — the Rust protocol already carries structured input; only
the `.ig` prelude and the web mapper are string-bound:

| Layer | File | Current `input` shape |
|---|---|---|
| `.ig` prelude `Decision` | `igweb.rs:68` | `InvokeEffect { target : String, input : String, idempotency_key : String }` — **String** |
| web mapper | `lib.rs:182` | `input: json!({ "input": get_str("input") })` — reads a **string**, wraps it |
| Rust protocol | `protocol.rs:101` | `ServerDecision::InvokeEffect { … input: Value … }` — **already `serde_json::Value`** |
| effect host | `effect_host.rs` | maps `target → machine route` (`target_routes`); capability identity in `EffectBridgeConfig.effect_passport` + signed recipe — **never in app input** |
| machine intent | `postgres_write.rs:46-55` | `PostgresWriteIntent { target: String, values: Value }`, `from_args(args: &Value)` — **`values` already `Value`** |

**So:** the protocol (`Value`) and the target intent (`values: Value`) are *already structured*. The only
string chokepoints are (1) the `.ig` prelude field type and (2) `map_decision`'s `get_str("input")`.

### The proven precedent (RespondView / RenderView)

`map_decision` already carries a typed `.ig` **record** across the seam as clean JSON:

```rust
"RespondView" => ServerDecision::Respond {
    response: ServerResponse::json(get_i("status") as u16,
        fields.get("view").cloned().unwrap_or(Value::Null)),  // VM record → Value, no string wrap
},
```

Prelude side: `RespondView { status, view : View }` / `RenderView { status, view : ViewArtifact }` — a
**concrete record field**, passed through verbatim. The comment (`lib.rs:171-173`, `199-203`) confirms: plain
records serialize to **clean JSON objects**; only *variant* values carry `__arm`/`__variant` discriminants.
A write-values record (`{ title, done }`) is a plain record → no tags. **This is exactly the mechanism
structured effect input needs.**

## Alternatives comparison

| Alt | Summary | Verdict |
|---|---|---|
| **A. Structured `input` value** | Re-type `input : String` → structured record; `map_decision` passes `fields.get("input")` through as `Value` (the `RespondView` pattern). Protocol already `Value`. | **RECOMMENDED** — minimal, reuses proven path, authority unchanged. |
| B. String + standardized JSON | App builds a JSON *string*, host parses. | Reject — string escaping / JSON construction is not the `.ig` authoring model (the whole reason the P18–P22 inline-JSON detour was retired). |
| C. Split arms (`InvokeEffect` + `InvokeStructuredEffect`) | Second arm. | Reject — duplicates the **same authority seam**, two paths to one host capability. |
| D. `Render`-style staged decision | Multi-stage. | Reject — writes already fit a final `InvokeEffect`; only the *payload* is narrow. |
| E. Host-side command-name convention | App emits target/key only; host reconstructs values. | Reject — moves domain semantics into the host, breaks the boundary. |

## Recommended v0 representation

**Alternative A, single arm, structured pass-through:**

```ig
-- app authors a plain record of column values (app-shaped, NOT framework-fixed)
compute d : Decision =
  InvokeEffect { target: "todo-create", input: { title: req.title, done: false },
                 idempotency_key: req.idempotency_key }
```

- **Prelude:** `InvokeEffect.input : String` → an **open structured record** position. Unlike `view : View`
  (a framework-fixed type), effect `values` are **app-shaped**, so `input` must accept *any* record. Reuse
  the existing **Unknown-compat** rule (record literals already type as `Unknown` and satisfy any nominal
  record field), i.e. type `input` as open/`Unknown` at this built-in arm — structure is validated **at the
  host** (mirroring how the renderer validates `View` structure at the Rust boundary, not in `.ig`).
- **Mapper:** `input: fields.get("input").cloned().unwrap_or(Value::Null)` — verbatim `RespondView` pattern.
- **Protocol/host/intent:** unchanged — `ServerDecision.input: Value` → effect host → `PostgresWriteIntent {
  target, values: <that Value> }` via `from_args`.

### Answers to the 10 required questions

1. **String-only field(s)?** `.ig` prelude `Decision::InvokeEffect.input : String` (`igweb.rs:68`) and the
   web mapper `get_str("input")` (`lib.rs:182`). The Rust protocol field is **already `Value`**.
2. **VM records as `serde_json::Value` without variant tags?** **Yes** — proven by `RespondView`/`RenderView`.
   Plain records → clean JSON objects; only variant values carry `__arm`/`__variant`. Write-values records are
   plain → tag-free.
3. **Existing string `InvokeEffect` tests?** Migrate. Tests asserting **target / idempotency_key / receipt /
   replay** shape are unaffected (they don't depend on `input` being a string). Only tests/fixtures that
   author `input` as a *string value* (e.g. `input: req.body`) switch to a record. Keep **one** explicit
   "input is a clean JSON object, not a wrapped string" regression.
4. **Source-compatible or second arm?** Single arm (reject C). It is a **breaking field-type change**
   (`String` → structured) for apps that authored a string input — but contained: no new arm, no protocol
   change, idempotency/receipt shape identical.
5. **Idempotency separation?** Stays a **separate field** in both prelude (`idempotency_key : String`) and
   protocol (`idempotency_key : Option<String>`). It is host-level dedup identity, **never** folded into
   `input`. (Confirmed separate today.)
6. **Host binds `target` → capability without app authority?** `MachineEffectHost.target_routes` (infra
   binding `target → machine route`, `effect_host.rs:39/58`) + `EffectBridgeConfig.effect_passport` + signed
   recipe hold capability identity. App emits only logical `target` + `values`. Boundary intact.
7. **Maps to `PostgresWriteIntent` / `WriteValues`?** `PostgresWriteIntent { target, values: Value }` +
   `from_args(&Value)` (`postgres_write.rs:46-55`). The structured `input` Value **is** `values`; logical
   `target` resolves (host binding) to the Postgres target. `values` is already `Value` → typed/structured
   survives.
8. **Denial cases?** App `input` must **not** contain `capability_id`, `operation`, `scope`, or raw SQL
   (host/recipe authority) → host rejects. Oversized payload → host bound/reject. Non-record / malformed
   input → typecheck or host error. `target` is logical only (no DSN / table DDL in app).
9. **Smallest implementation card?** `LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-P7` (below).
10. **Unblocks local Postgres write?** It unblocks the **structured payload crossing the seam** only. Real
    local execution still needs `LAB-TODOAPP-API-LOCAL-POSTGRES-P8` (DSN / adapter / runner). Another card
    required.

## Migration / backward-compat story

- **Not source-compatible** at the `.ig` authoring level for the `input` field (String → record). The fix is
  mechanical: `input: req.body` → `input: { …fields }`.
- **Fully compatible** for the receipt / idempotency / replay / target contracts — unchanged shapes, so the
  fake-host write/e2e assertions on those survive.
- Keep one regression proving `input` serializes as a **clean JSON object** (no `{"input": "<string>"}`
  wrapper, no double-parse) — the literal thing P5 flagged.

## Authority boundary (exact)

- **App (`.ig`/`.igweb`):** logical `target` + structured `values` + `idempotency_key`. Nothing else.
- **Host (Rust):** `target → machine route` binding, capability identity (`effect_passport` + signed recipe),
  operation/scope, DSN, payload bounds, denial of forbidden keys.
- **Machine:** builds + executes `PostgresWriteIntent`, emits receipt, enforces idempotency.
- The structured `input` is **data**, never authority — same discipline as the wire→effect contour.

## Target test matrix (for P7)

| Case | Expectation |
|---|---|
| record `input` crosses seam | `ServerDecision.input` is the clean JSON object (no string wrap) |
| nested record `input` | nested object preserved verbatim |
| `target` + `idempotency_key` unchanged | same as P5 fake-host shape |
| `input` record → `PostgresWriteIntent.values` (fake host) | typed values survive byte-for-byte |
| idempotency replay | second call same key → one business row, receipt replay (unchanged) |
| forbidden key in `input` (`capability_id`/`operation`/`scope`) | host denies |
| raw SQL string in a value | treated as opaque data, never executed as SQL |
| oversized payload | host rejects |
| non-record `input` | typecheck/host error |
| existing string-shape regression | one kept/migrated test proves clean object |

## Local Postgres dependency chain (after this card)

```
P6 (this, readiness)  →  P7 STRUCTURED-EFFECT-INPUT (impl: prelude+mapper, fake-host proof)
                       →  P8 TODOAPP-API-LOCAL-POSTGRES (real DSN/adapter/runner, gated)
```

P7 proves typed values survive target→values on the **fake** host. P8 (separately gated — live DSN/DDL) does
real local execution. Do not open P8 until P7's fake-host tests prove the typed payload crosses.

## Non-goals (honored)

No implementation; no live Postgres / DSN / DDL; no effect execution in `.ig`; no capability id / operation /
scope / raw SQL in app-authored files; no runner async productization; no queue/job/export; no canon claim.

## Recommendation

**Proceed with Alternative A.** The seam is already `Value` end-to-end except two string chokepoints, and the
`RespondView` record-pass-through is a working, tested precedent. Open
`LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-P7`.

---

*Readiness/design only — verified against live `igweb.rs`, `igniter-web/src/lib.rs`,
`igniter-server/src/protocol.rs`, `effect_host.rs`, `postgres_write.rs` (2026-06-20). Protocol + target intent
already carry `serde_json::Value`; only the `.ig` prelude type and `map_decision` are string-bound. v0 =
re-type `input` to a structured record + pass-through via the proven `RespondView` path; authority host-side;
local Postgres needs P8.*
