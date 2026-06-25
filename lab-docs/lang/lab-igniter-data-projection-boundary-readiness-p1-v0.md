# lab-igniter-data-projection-boundary-readiness-p1-v0

Card: `LAB-IGNITER-DATA-PROJECTION-BOUNDARY-READINESS-P1`
Route: standard / architecture readiness · Skill: idd-agent-protocol
Status: readiness packet (no code changed; no canon claim; nothing here is "implemented today")
Date: 2026-06-25

> **Authority boundary.** This packet *decides nothing about canon* and *implements nothing*. It is
> evidence + a recommended direction, verified against live `igniter-lab` source. It names the boundary
> for external data entering `.ig`, picks a v0 shape, and proposes the first two implementation cards.
> Live source wins over any older proof prose (per `server/igniter-web/IMPLEMENTED_SURFACE.md` Historical
> docs rule). Every concrete capability claim below carries a `file:line` citation.

---

## 1. Live current-state summary (verify-first)

### 1.1 The seam that exists today

A read flows through five live stages. The first three are typed; the boundary into `.ig` is **a JSON
string**:

```text
.ig contract → typed QueryPlan record         (app owns the logical query)
  → host PostgresReadExecutor gates + decodes  (host owns allowlist, field kinds, bounds)
  → typed serde_json rows (Int/Bool/Json kept) (host has structured, typed rows in hand)
  → StagedReadHost stringifies rows            ← THE FLATTENING POINT
  → continuation input rows_json : String      (app can only compare/echo; no fields)
```

Stage-by-stage, with citations:

1. **App emits a typed `QueryPlan` record** — never SQL. Fields `source / op / projection /
   filters / order_by / limit`. App side: `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig:39`
   (`type QueryPlan { … projection : Collection[String]  filters : Collection[QueryFilter] … }`).
   Host side mirror: `runtime/igniter-machine/src/postgres_read.rs:53` (`pub struct QueryPlan`).

2. **Host gates the plan before any adapter call** — raw-SQL refusal, source allowlist, read-only
   (mutation refusal), op allowlist, field allowlist, typed-predicate validation, row-limit **clamp**
   (not denial). `runtime/igniter-machine/src/postgres_read.rs:455-539`. The schema authority is a
   **host-side `PostgresReadPolicy`**, not contract input and not DB introspection
   (`postgres_read.rs:316-335`).

3. **Host decodes rows into typed values.** Each allowlisted field has a host-declared decode kind —
   `PostgresReadValueKind ∈ { Text, Integer, Boolean, Json, Timestamp, DecimalString, Array }`
   (`postgres_read.rs:299-314`). The executor returns a structured outcome carrying typed rows **plus
   provenance**: `{ kind: "rows"|"empty", source, rows: Array, count, effective_limit, row_limit_clamped }`
   (`postgres_read.rs:517-527`). The fake adapter "stores already-typed `serde_json::Value` rows … preserves
   int/bool/json/null types" (`postgres_read.rs:602-603`); the real adapter casts/binds per field kind
   (`runtime/igniter-machine/IMPLEMENTED_SURFACE.md:121`).

4. **The host flattens the typed rows to a JSON string.** `StagedReadHost::execute` takes
   `outcome.result["rows"]` and does `serde_json::to_string(...)` → `StagedReadResult::Rows(rows_json: String)`
   (`server/igniter-web/src/read_dispatch.rs:109-117`). **All of `kind / source / count / effective_limit /
   row_limit_clamped` are dropped here** — they exist host-side and never cross into `.ig`.

5. **The continuation receives a `String`.** `dispatch_with_read` re-dispatches `then` with
   `{ req, rows_json, carry }` (`server/igniter-web/src/lib.rs:118-124`). The continuation declares
   `input rows_json : String` and can only string-compare or echo it
   (`todo_handlers.ig:161-166` `Respond { body: rows_json }`; `todo_handlers.ig:171-181` `if rows_json == "[]"`).

This is **declared, not implemented** by design. `server/igniter-web/IMPLEMENTED_SURFACE.md:32` rates
"Typed row destructuring in the continuation" as `designed (not implemented) — Continuation receives rows
as a JSON string (rows_json); no typed columns. Humble v0." Confirmed again at
`IMPLEMENTED_SURFACE.md:103` and `examples/todo_postgres_app/API.md:248`.

**Key consequence:** the typing already happened (stage 3). The flattening in stage 4 *throws it away*. The
boundary this card names is not "how do we type the rows" — the host already typed them — it is **"what
Igniter-native value crosses at stage 4 instead of a `String`."**

### 1.2 What the language can already do with rows (live)

The `.ig` half needed to *consume* typed rows is **already exercised in fleet apps** over injected rows:

- **Records:** declared `type X { f : T }`, literal construction `{ f: v }`, dot field access `r.f`,
  spread/update `{ ...base, f: v }`. Typechecker: `lang/igniter-compiler/src/typechecker.rs` (record
  literal inference ~`:4743`, field access ~`:3953`, spread ~`:4797`). Record literals infer to `Unknown`
  then upgrade to the named type from the surrounding output-type context.
- **Collection HOFs:** `map`, `filter`, `fold`, comprehensions are live;
  `map(coll, x -> call_contract("Helper", x))` is the proven shape
  (`lang/igniter-compiler/src/typechecker/stdlib_calls.rs` map ~`:1226`, filter ~`:885`, fold ~`:2082`).
- **Typed row collection + transform — already real contract I/O:**
  - `apps/igniter-apps/query_engine/types.ig:17` — `type Row { id: Integer, age: Integer, city: String,
    active: Integer }`, consumed as `input rows : Collection[Row]` (`query_engine/eval.ig:74`) with typed
    field access inside a HOF: `filter(rows, row -> … row.city == p.str … row.age …)`
    (`query_engine/eval.ig:47,76`). The header even names the boundary: *"the rows … are injected at the
    boundary"* (`query_engine/types.ig:9-11`).
  - `apps/igniter-apps/batch_importer/types.ig:18` — `type RawRow { row_id: Integer, amount: Integer,
    email: String }`, consumed as `input rows : Collection[RawRow]`
    (`batch_importer/validate.ig:36`), transformed `map(rows, r -> call_contract("ValidateRow", r))`
    (`batch_importer/validate.ig:37`).
- **View half is fully proven** — but **only over literal fixtures, never over read rows.** The live
  authoring chain is `compute todos : Collection[TodoItem] = [ … literals … ]` →
  `filter(todos, t -> t.done == false)` → `map(pending, t -> call_contract("TodoLabel", t))` →
  `Collection[HtmlNode]` → `FormView` → `RenderView { status, view : ViewArtifact }`
  (`server/igniter-web/examples/todo_view_app/todo_views.ig:138-148,154-166`). The host serializes the
  typed `ViewArtifact` record and projects it to escaped HTML (`server/igniter-web/src/lib.rs:415-427`).

### 1.3 What the language deliberately cannot do (live) — the load-bearing gaps

- **No in-language JSON parser.** There is no `json_parse` / `from_json` callable in `.ig`. JSON↔value is a
  **host (serde) concern**; the host crosses JSON objects as `Map[String, Unknown]` (e.g. `req.body_json`,
  `req.query` at `server/igniter-web/src/lib.rs:304-307,311-315`) and `.ig` reads typed keys via
  fail-closed `map_get_string` (`stdlib_calls.rs` ~`:2497`). So "just parse JSON strings in `.ig`" is **not
  available** without first building a parser in the language.
- **No string→scalar coercion in-language.** A repo-wide grep finds only `stdlib.math.to_float`
  (Integer→Float, `stdlib_calls.rs:329`). There is **no** `to_integer` / `parse_int` / string→Bool /
  string→Decimal. `map_get_string` returns `Option[String]` only. **Therefore a stringly row surface
  (`Collection[Map[String, Unknown]]`, all-string values) would strand every non-text column** — `.ig`
  could not turn `"42"`→Integer or `"true"`→Bool. The `batch_importer` doctrine says the same thing in
  source: *"no String→Int parse in CORE"* (`batch_importer/types.ig:15`).
- **No user-record generics.** `Collection[T]`, `Map[K,V]`, `Result[T,E]`, `Option[T]` are built-in
  parametric; **user records are not** (the prelude uses concrete `Collection[HtmlNode]` etc.,
  `lang/igniter-compiler/src/igweb.rs:63-68`). So a generic `Dataset[T]` envelope is **not expressible
  today** — provenance must ride either a fixed (non-generic) sidecar record or bare alongside the rows.
- **`Unknown` is allowed in *input* position** (the prelude proves it: `Request.body_json : Map[String,
  Unknown]`, `ReadThen.plan : Unknown`, `InvokeEffect.input : Unknown` — `igweb.rs:30,82,87`), but is
  **forbidden in output annotations** (OOF-MAP3). The uncertainty marker may enter `.ig`, not leave it.

---

## 2. Glossary / proposed vocabulary

| Term | Meaning (proposed) |
| --- | --- |
| **Data Projection Boundary** | The seam where a host-owned external read becomes a typed Igniter value. Matches the card title. This is *the* thing being named. |
| **`HostDataset`** (host-internal) | The bounded, typed, provenance-bearing result the host already builds at `postgres_read.rs:517-527` (`{ kind, source, rows, count, effective_limit, row_limit_clamped }`). Not an `.ig` type — it is the host's hand before projection. |
| **Typed row projection** (the v0 crossing) | The act of crossing `HostDataset.rows` into `.ig` as `Collection[<AppRow>]`, where `<AppRow>` is an **app-declared record** (e.g. `TodoRow`). The rows are already decoded per host `PostgresReadValueKind`; projection = "stop stringifying, materialize as records." |
| **`<AppRow>`** | An app-owned record type mirroring the projected columns (precedent: `query_engine` `Row`, `batch_importer` `RawRow`). The app owns this type and its field meaning. |
| **`DatasetMeta`** (provenance sidecar) | A fixed (non-generic) record carrying the product-relevant provenance the host already has: `{ source : String, count : Integer, truncated : Bool }` (`truncated` ← `row_limit_clamped`). Crosses beside the rows because user-record generics don't exist. |
| **`decoder` / `RowResult`** | The lower-level fallback: an app contract `RawValue -> Result[Row, Error]` (or the `variant RowResult { Valid | Invalid }` shape proven in `batch_importer/types.ig:35-38`). For untrusted/file/API input, NOT for host-typed relational reads. |
| **`transform`** | A pure collection HOF over the typed rows: `map`/`filter`/`fold` (+ `call_contract` callbacks) from `Collection[<AppRow>]` to a domain/view model. Already the proven `query_engine`/`batch_importer`/`todo_view_app` shape. |
| **ESCAPE boundary** | The repo's existing name (`batch_importer/types.ig:13-15`) for "untyped bytes → typed rows" — i.e. exactly the projection/decoder seam. We adopt this term rather than invent one. |

---

## 3. Comparison of alternatives

Scored for: DX, type safety, host authority, error taxonomy, replay/provenance, implementation size,
generalization beyond Postgres. ✅ strong · ◐ partial · ❌ weak.

| # | Alternative | DX | Type safety | Host authority | Error taxonomy | Replay/prov. | Impl size | Generalizes | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Keep `rows_json : String` + add JSON parser helpers in `.ig`** | ❌ stringly; build whole JSON+coercion stack in-lang | ❌ | ◐ host typed then re-stringified (lossy) | ❌ parse errors become app-side | ◐ | ❌ huge (new in-lang parser + coercions) | ◐ | **Reject.** Re-derives in `.ig` what the host already did; needs a JSON parser + scalar coercions the language deliberately lacks (`§1.3`). Violates the card's design bias. |
| 2 | **`Collection[Map[String, Unknown]]` generic row surface** | ◐ `map_get_string` per field | ◐ keys typed-as-string only | ✅ | ◐ missing-key fail-closed | ✅ | ◐ small (stop stringify; pass as maps) | ✅ | **Fallback only.** Works, but **strands Integer/Bool/Decimal** — no string→scalar coercion (`§1.3`). Acceptable for genuinely heterogeneous/unknown-schema sources; wrong default for host-typed relational reads. |
| 3 | **Host-side typed projection into app-declared records → `Collection[<AppRow>]`** | ✅ `r.title`, `r.done` typed | ✅ Int/Bool/Decimal preserved | ✅ host is schema authority (`PostgresReadValueKind`) | ✅ mismatch = host error (rows stay total) | ✅ host has all of it | ◐ small-medium: stop stringify + bind JSON array→`Collection[Record]` | ✅ | **Recommended v0.** The host already decodes typed rows; this just stops discarding the types. Lands on the already-exercised `Collection[Row]` shape (`query_engine`, `batch_importer`). |
| 4 | **Decoder contracts `RawValue -> Result[<Row>, Error]` as explicit app validation** | ◐ per-row, verbose | ✅ | ◐ app re-validates host-typed data | ✅ explicit `Result`/`RowResult` | ✅ | ◐ medium | ✅ | **Keep as lower layer.** Right for untrusted/file/API input (`batch_importer` precedent). Wrong as the *primary* DX for host-owned relational reads — it duplicates the host's gating. |
| 5 | **Projection / named `transform` contracts (`ProjectRows[<Row>]`)** | ◐ extra ceremony | ✅ | ✅ | ◐ | ✅ | ◐ medium (new contract category) | ✅ | **Defer.** A `transform` is just a pure HOF over `Collection[<AppRow>]` (#3 + existing `map`/`filter`). No new contract category needed in v0; revisit if a declarative projection attached to `QueryPlan` proves valuable. |
| 6 | **A `Dataset` record carrying `rows`, `schema`, `provenance`, `warnings`** | ✅ one value | ✅ | ✅ | ✅ | ✅ best | ◐ but **needs user-record generics** (`Dataset[T]`) — not in language (`§1.3`) | ✅ | **Partly defer.** Full `Dataset[T]` blocked on generics. Approximate now with bare `Collection[<AppRow>]` + a **fixed `DatasetMeta` sidecar** (#3 + provenance). Promote to `Dataset[T]` if/when user generics land. |
| 7 | **DataFrame / table abstraction** | ✅ rich | ✅ | ✅ | ✅ | ✅ | ❌ very large (columnar engine, dynamic schema) | ✅ | **Reject for v0.** Out of scale; `query_engine/types.ig:13-14` already files "heterogeneous rows / dynamic field projection" as deferred pressure. |

---

## 4. Recommended v0 direction

**Adopt alternative #3 — host-side typed projection into an app-declared row record — as the primary
Data Projection Boundary, with #4 (decoder/`RowResult`) as the named lower-level fallback and a fixed
`DatasetMeta` provenance sidecar (a slice of #6).**

```text
QueryPlan(projection = ["id","title","done"])           — app owns the logical query
  → host executes with allowlist + typed field policy    — host owns authority + decode kinds
  → HostDataset rows: typed, bounded, with provenance     — already built at postgres_read.rs:517
  → typed projection: cross rows as Collection[TodoRow]    — STOP stringifying (the one new move)
     (+ optional DatasetMeta { source, count, truncated }) — surface the provenance host already has
  → app transform: map/filter over Collection[TodoRow]     — already-proven HOF shape
  → view model / domain contract                           — app owns
```

Why this is the right v0, grounded in live source:

1. **The host already did the hard part.** Rows are decoded to typed `serde_json::Value` per
   `PostgresReadValueKind` (`postgres_read.rs:602-603`, `:299-314`). Crossing them as records is *removing*
   the lossy `to_string` at `read_dispatch.rs:111`, not adding new typing.
2. **The language cannot reconstruct the types itself** (no JSON parser, no string→scalar coercion, `§1.3`).
   So any boundary that hands `.ig` strings (alts #1, #2) permanently strands Integer/Bool/Decimal columns.
   Typed projection is the *only* option that keeps the rows usable.
3. **The target shape is already real I/O.** `Collection[Row]` / `Collection[RawRow]` are live contract
   input types with typed field access in HOFs (`query_engine/eval.ig:74-76`,
   `batch_importer/validate.ig:36-37`). v0 reuses an exercised surface; it does not invent one.
4. **The app keeps schema authority over *meaning*; the host keeps authority over *acquisition + decode +
   bounds*.** The app declares `type TodoRow { … }`; the host's `PostgresReadPolicy` still owns the
   allowlist and field kinds. Two authorities, cleanly split — the same split already live for reads
   (`read_dispatch.rs:7-10`).

**The one genuinely new move** is at stage 4: instead of `serde_json::to_string(rows)`, cross the rows array
as a structured value the VM materializes as `Value::Record`s, bound to a continuation input
`rows : Collection[<AppRow>]`. The runtime can already build records from JSON (`from_json → Value::Record`)
and already crosses structured records both ways (`req.body_json` in; `InvokeEffect.input`/`WriteIntent.values`
out — `lib.rs:391-408`). Proving that array→`Collection[Record]` input binding makes `r.field` access work is
exactly the smallest next proof card (`§8`).

---

## 5. Explicit decoder-vs-transform decision

**Decision: `transform` is the primary DX; `decoder` is the lower-level fallback. They are different jobs at
different trust levels, not competitors.**

- **`transform`** = pure HOF over **already-typed** rows: `Collection[<AppRow>] → map/filter/fold →
  domain/view model`. Use it for **host-owned relational reads**, where the host is the schema authority and
  has already gated + decoded the data. A transform never needs to validate the *types* (the host
  guaranteed them) — it only reshapes. This is the proven `query_engine`/`todo_view_app` shape and the v0
  default. A transform is **not a new contract category** — it is `map`/`filter` you already have.

- **`decoder`** = `RawValue -> Result[<Row>, Error]` (or `variant RowResult { Valid | Invalid }`,
  `batch_importer/types.ig:35-38`). Use it where the source is **untrusted or unschematized** and the *app*
  must own validation: user JSON bodies, CSV/file imports, third-party HTTP payloads, anything crossing the
  ESCAPE boundary without a host typed-field policy. A decoder produces typed rows *and* an error channel.

Rule of thumb: **if the host owns a typed field policy for the source, you get a `transform` over typed
rows. If it doesn't, you write a `decoder` that yields `Result`/`RowResult`.** Decoders sit *under* the
projection surface; they are the escape hatch, not the everyday path — exactly as the card's design bias
asks.

---

## 6. Error ownership taxonomy

Who owns each mismatch, verified against the live gates:

| Mismatch | Owner | Surfaced as | Live anchor |
| --- | --- | --- | --- |
| Source / field not allowlisted; raw-SQL shaped; op not allowed | **Host** (policy gate) | `Denied` → **403** before adapter | `postgres_read.rs:463-499`, `read_dispatch.rs:119-127`, `lib.rs:128-131` |
| Malformed / over-broad plan (bad predicate, too many `in` values / order clauses) | **Host** | `PermanentFailure` | `postgres_read.rs:504-508` (`validate_predicates`) |
| Adapter unavailable / transient / query error | **Host** | `HostError` → **503** (unknown/retryable kept epistemic) | `postgres_read.rs:529-537`, `read_dispatch.rs:128-130`, `lib.rs:133-136` |
| Row limit exceeded | **Host** | **Clamp, not error** — `effective_limit` + `row_limit_clamped` flag | `postgres_read.rs:510-513` |
| Empty result set (e.g. account exists, no todos) | **App** (product decision) | `200 []` vs `404` — *not an error* | `todo_handlers.ig:344-357` (`CheckAccountThenList`) |
| User request body / JSON field mismatch | **App** (validation) | **400** via `body_kind` + fail-closed `map_get_string` | `todo_handlers.ig:213-221` (`ResolveCreateTitle`), `lib.rs:299-307` |
| File / API / untrusted import mismatch | **App** (decoder) | `Result` / `RowResult { Invalid }` | `batch_importer/validate.ig:22-28`, `types.ig:35-38` |
| **Typed-projection mismatch** (host says Integer, value isn't decodable) | **Host** ← *new boundary's rule* | host read error (503/permanent); rows that reach `.ig` stay **total + typed** | proposed; consistent with host being schema authority (`postgres_read.rs:299-314`) |

**Provenance travel.** The host already computes `kind / source / count / effective_limit /
row_limit_clamped` (`postgres_read.rs:520-526`) and currently **drops all of it** at `read_dispatch.rs:111`.
Recommendation:

- **Visible to `.ig`** (product-relevant): `source`, `count`, and `truncated` (← `row_limit_clamped`, so a
  handler can drive "load more"/cap UX). Carried by the fixed `DatasetMeta` sidecar.
- **Host diagnostics only** (never crossed): `plan_digest`, `correlation_id`, receipt id, `effective_limit`
  internals, DSN/capability/scope (already host-only — `read_dispatch.rs:23-28,85-105`).

---

## 7. How this unblocks Todo HTML — without becoming Todo-specific

The Todo-HTML chain is **two proven halves with one missing link**:

```text
[ READ HALF — typed up to stage 3, then stringified ]      [ VIEW HALF — fully proven over fixtures ]
QueryPlan → host gates+decode → typed rows ──✂──rows_json   Collection[TodoItem] → filter → map →
                                   (string)                  Collection[HtmlNode] → FormView → RenderView
```

- The **view half already works end-to-end over literal `Collection[TodoItem]`**
  (`todo_view_app/todo_views.ig:138-148`, render at `lib.rs:415-427`).
- The **read half is typed right up to the cut** (`postgres_read.rs:517`), then flattened
  (`read_dispatch.rs:111`).

The *single* missing link is the typed projection of `§4`: cross the read rows as `Collection[TodoRow]`
instead of `rows_json : String`. Once that lands, the existing `map(rows, r -> call_contract("TodoLabel",
r))` pattern joins the halves with **no Todo-specific machinery** — `TodoRow`, `TodoLabel`, `FormView` are
all ordinary app contracts over the generic `Collection[<AppRow>] → Collection[HtmlNode] → RenderView`
surface. The boundary stays generic: **any** app declares **its** row record and **its** transform; Todo is
just the first consumer, exactly as it is the first consumer of routing and `RenderView` today.

Pieces still missing for the full Todo-HTML demo (named, **not** implemented here):

1. Typed-row continuation crossing (the projection — card #1 below). *Language/runtime.*
2. Provenance sidecar (`DatasetMeta` — folded into card #2). *Host.*
3. Nothing else — the `Collection[<AppRow>] → map → HtmlNode → RenderView` path is already live.

---

## 8. First two implementation cards (acceptance sketches)

> Both are **DB-free** (fake Postgres adapter), reuse existing harness patterns
> (`server/igniter-web/tests/todo_postgres_read_host_tests.rs`), add **no** `.igweb` syntax, **no** new
> Postgres feature, and make **no** canon claim. They promote "Typed row destructuring" from `designed`
> → `harness-proven`.

### Card 1 — `LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6`

**Goal.** Cross a read's typed rows into a continuation as `Collection[<AppRow>]` (not a JSON string) and
prove typed field access + HOF transform over them. Smallest possible slice: fake rows → app-declared
`TodoRow` collection → `r.title` / `r.done` work.

**Shape.**
- Host: an alternate staged-read result that passes `outcome.result["rows"]` through **as a structured
  value** (materialized to `Value::Record`s) instead of `serde_json::to_string` (`read_dispatch.rs:111`).
- App: a continuation `input rows : Collection[TodoRow]` whose body does typed field access in a HOF.

**Acceptance.**
- [ ] A harness test (sibling of `todo_postgres_read_host_tests.rs`) drives `ListTodosByAccount → QueryPlan
      → fake PostgresReadExecutor → rows → continuation` where the continuation declares
      `input rows : Collection[TodoRow]`.
- [ ] The continuation body proves typed access: e.g. `compute n = count(filter(rows, r -> r.done == false))`
      and/or `map(rows, r -> r.title)` — compiles and runs, returning the expected typed result over fake rows.
- [ ] Integer/Bool columns survive (a row with `done` as a real Bool, an `id`/count as Integer — not a string).
- [ ] DB-free; no `.igweb` change; no new Postgres feature; `git diff --check` clean.
- [ ] On mismatch (a row missing a declared field / wrong kind) the **host** fails the read (rows reaching
      `.ig` stay total) — encode the `§6` rule as a test.

**Open risk to resolve in the card:** confirm the VM binds a JSON array-of-objects to a
`Collection[<Record>]` input so `r.field` resolves as record access (via `from_json → Value::Record`), and
that record-literal/`Unknown` inference doesn't block the continuation's output. This is the one real
language/runtime question; everything else is plumbing.

### Card 2 — `LAB-IGNITER-DATA-PROJECTION-DATASET-META-AND-HTML-P3`

**Goal.** (a) Surface the provenance the host already drops, via a fixed `DatasetMeta` sidecar; (b) join the
read half to the view half — render an HTML list from typed read rows. Depends on Card 1.

**Shape.**
- Host: alongside `rows`, cross `meta = { source, count, truncated }` (`truncated ← row_limit_clamped`,
  `postgres_read.rs:513,526`).
- App: `Collection[TodoRow] → map(r -> call_contract("TodoRowToNode", r)) → Collection[HtmlNode] →
  FormView → RenderView` — reusing the live `todo_view_app` chain (`todo_views.ig:138-148`).

**Acceptance.**
- [ ] A harness test renders an HTML `<form>`/list whose items come from **typed read rows** (not literal
      fixtures), proving the read→view join.
- [ ] `truncated` is exposed to `.ig` and a test shows a clamped read (`row_limit_clamped == true`) reaching
      a handler that can react (e.g. emit a "more" affordance).
- [ ] `DatasetMeta` is source-agnostic (no `todo`/Postgres-specific fields) — the same record would carry an
      HTTP/CSV read's provenance.
- [ ] DB-free; reuses the existing renderer (`lib.rs:415-427`); no canon claim; `git diff --check` clean.

---

## 9. Generalization beyond Postgres

The boundary is `external source → host authority/exec → bounded typed dataset → typed projection →
Collection[<AppRow>] → app transform`. Only stages 1-2 are source-specific; the projection contract is
source-agnostic. The host-side `PostgresReadValueKind` generalizes to a **per-source field decode policy**.

| Source | Host owns (acquire + type + bound + provenance) | App owns (projection target + transform) | Path |
| --- | --- | --- | --- |
| Postgres relational read | `PostgresReadPolicy` field kinds; allowlist; row clamp (`postgres_read.rs`) | `TodoRow` + `map`/`filter` | #3 transform |
| HTTP JSON API response | host fetch (`http::HttpCapabilityExecutor`, `igniter-machine`); declared field decode | `<ApiRow>` + transform; or **decoder** if untrusted | #3 or #4 |
| CSV / file import | host parse at ESCAPE boundary (bytes→tokens) | `RawRow` + **decoder** → `RowResult` (proven, `batch_importer`) | #4 decoder |
| Report / export descriptor | inverse: app builds `Collection[<Row>]`, host serializes | `<Row>` + transform | #3 reversed |
| Scientific dataset | host reader + typed field policy | `<Reading>` + fold/aggregate | #3 transform |
| Ledger / tbackend facts/history | facts already typed in the kernel (`read_bitemporal`, `igniter-machine`) | `<Fact>` projection | #3 transform |
| Remote-node payload | host transport + decode policy | `<Row>` + transform; decoder if untrusted | #3 or #4 |

The unifying contract: **host = acquisition + typing + bounding + provenance; app = the typed row record +
transform + view model.** Same split for every source; only the host executor changes.

---

## Appendix A — pseudo-code (illustrative; NOT implemented)

> Sketches only — naming/shape for the next cards. Nothing below compiles today.

**A.1 Typed projection (recommended v0) — continuation over typed rows**

```text
type TodoRow {
  id         : String
  account_id : String
  title      : String
  done       : Bool
}

-- host crosses the read's rows as Collection[TodoRow] (no JSON string), plus a provenance sidecar.
pure contract AccountTodoIndexFromRows {
  input req  : Request
  input rows : Collection[TodoRow]
  input meta : DatasetMeta            -- { source : String, count : Integer, truncated : Bool }
  compute pending : Collection[TodoRow] = filter(rows, r -> r.done == false)
  compute nodes   : Collection[HtmlNode] = map(pending, r -> call_contract("TodoRowToNode", r))
  compute view    : ViewArtifact = call_contract("FormView", "Todos", nodes)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
```

**A.2 Decoder fallback (untrusted/file/API) — the lower layer, `batch_importer` shape**

```text
variant RowResult { Valid { record : TodoRow }  Invalid { key : String, message : String } }

pure contract DecodeTodoRow {                  -- RawValue -> Result-like, app owns validation
  input raw : Map[String, Unknown]
  compute title : String = or_else(map_get_string(raw, "title"), "")
  compute result : RowResult = if title == "" {
    Invalid { key: or_else(map_get_string(raw, "id"), "?"), message: "title required" }
  } else {
    Valid { record: call_contract("MakeTodoRow", raw) }
  }
  output result : RowResult
}
```

**A.3 Why NOT the stringly map surface (rejected default)**

```text
-- Collection[Map[String, Unknown]] strands typed columns: map_get_string returns Option[String],
-- and there is NO to_integer / to_bool in the language (§1.3). `done` and `id` would be unusable as
-- Bool/Integer — only re-stringifiable. Hence host-side typed projection (A.1) is the v0 default.
```

---

## Reporting

- **Recommended vocabulary:** *Data Projection Boundary*; the v0 crossing is a **typed row projection** into
  an **app-declared `<AppRow>` record** → `Collection[<AppRow>]`, with a fixed **`DatasetMeta`** provenance
  sidecar. Lower layer: **`decoder` / `RowResult`** (the `batch_importer` ESCAPE-boundary shape).
- **Chosen v0 direction:** alternative #3 — **host-side typed projection into app-declared records** — because
  the host already decodes typed rows (`postgres_read.rs:602`), the language cannot reconstruct types itself
  (no JSON parser / no string→scalar coercion, `§1.3`), and `Collection[Row]` is already real contract I/O
  (`query_engine`, `batch_importer`).
- **Deliberately lower-level / deferred:** `decoder`/`RowResult` (fallback, not default); generic `Dataset[T]`
  envelope (blocked on user-record generics); declarative `transform`/projection-attached-to-`QueryPlan`
  (a HOF suffices in v0); DataFrame/columnar (out of scale).
- **Next cards:** `LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6` (typed rows into a continuation;
  smallest proof), then `LAB-IGNITER-DATA-PROJECTION-DATASET-META-AND-HTML-P3` (provenance sidecar + read→
  HTML join). Both DB-free, harness-only, no canon claim.
- **Exact verification commands** (run; both clean — `§ below`):

```bash
rg -n "rows_json|body_json|ReadThen|Map\[String, Unknown\]|Collection\[.*Row|RenderView|QueryPlan" \
  server/igniter-web runtime/igniter-machine lang/igniter-compiler lang/igniter-vm \
  > /tmp/igniter-data-projection-live-grep.txt

git diff --check
```
