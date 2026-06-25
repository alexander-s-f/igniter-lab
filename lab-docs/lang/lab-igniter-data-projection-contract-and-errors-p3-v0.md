# lab-igniter-data-projection-contract-and-errors-p3-v0

Card: `LAB-IGNITER-DATA-PROJECTION-CONTRACT-AND-ERRORS-READINESS-P3`
Route: standard / architecture readiness · Skill: idd-agent-protocol
Status: readiness packet (no code changed; no host-config/compiler/runtime change; no canon claim)
Date: 2026-06-25
Builds on: P1 boundary packet · P2 materialization packet (`lab-docs/lang/lab-igniter-data-projection-{boundary-readiness-p1,materialization-readiness-p2}-v0.md`)

> **Authority boundary.** Design only. Decides nothing about canon, implements nothing, changes no host
> config format. Every concrete claim carries a `file:line` citation against live `igniter-lab` source.

---

## Headline

**The projection target is declared in exactly one place — the continuation's input type
`input rows : Collection[<AppRow>]` — and the host *honors that type by proof, not by trust*: at load
time it reconciles its own field-kind schema authority against the `<AppRow>` shape (read from the
compiled IR) and fails closed with a stable runner diagnostic on drift. No `row_type` on
`ReadThen`/`QueryPlan`, no row-type in host config, no new `Decision` variant, no `DatasetMeta` generics.
Rows that reach `.ig` are total + typed; schema drift becomes a deployment-time error, never app business
logic.**

The pattern in one line: **a continuation input type is a *typed read contract* the host satisfies by
reconciling it against its schema authority at boot — the same way it resolves `*_env` secrets before bind.**

---

## 1. The philosophy fork this card resolves

Igniter already fixes the authority for host-owned reads: **the host is the schema authority**
("Schema authority = host-side `PostgresReadPolicy` (not contract input, not introspection)" —
`runtime/igniter-machine/src/postgres_read.rs:296-298`), and app-side row types are **advisory mirrors**
of that authority ("Advisory row mirrors (host-owned schema is the authority; these are documentation)" —
`server/igniter-web/examples/todo_postgres_app/todo_handlers.ig:14`).

That gives a precise answer to "how does the host avoid trusting the app too much?" (Q2): **it doesn't trust
the app's row type — it proves its own authoritative policy can *produce* that type.** The app declares the
*view it requires*; the host proves its schema can *satisfy* that view. Neither side trusts the other:

- the app cannot widen what it reads (projection ⊆ host allowlist — already enforced,
  `postgres_read.rs:483-499`);
- the app cannot mis-type a field without the host catching it (the boot reconciliation, §3);
- the host never invents app *meaning* (what `done`/`title` mean to the domain stays in `.ig`).

**The shortcut to avoid** (and the reason this card exists): "just cross records and let the typechecker
sort it out." That skips reconciliation — and P2 showed the consequence is *silent-wrong* values
(`Value::String("true") == Value::Bool(false)` is `false`, `value.rs:6`) and *path-dependent* field-access
errors (error | Nil | record-passthrough, `vm.rs:2762/2667/3887/3912`). Reconciliation is the fundamental
piece that turns `Collection[AppRow]` from a *hope* into a *promise*. Skipping it re-imports the P2 drift
hazard into app runtime.

---

## 2. Where the row type is declared (Q1)

**Recommendation: the continuation input type, and nowhere else.**

```text
-- the continuation already declares its inputs as ordinary typed contract inputs; the row type lives here:
pure contract AccountTodoIndexFromRows {
  input req  : Request
  input rows : Collection[TodoRow]      ← THE single projection-target declaration
  input meta : DatasetMeta              ← provenance sidecar (§4)
  …
}
type TodoRow { id : String  account_id : String  title : String  done : Bool }   ← app owns the type
```

The host derives the projection spec by reading `then`'s `rows` input type from the compiled IR — the IR
already carries it: `lang/igniter-vm/src/compiler.rs:213` documents
`contract_obj["inputs"] — array of { "name": "...", "type": { ... } }`, and the machine already introspects
contract IR for exactly this kind of question (`discover_effect_surface`,
`runtime/igniter-machine/src/service_loop.rs:67`). So the type is stated once, in the Igniter-native place,
and is *both* compiled against (`r.title` typechecks against `TodoRow`) *and* enforced by the host (§3).

Alternatives, evaluated and rejected:

| Option | Why rejected |
| --- | --- |
| `ReadThen` carries `row_type : String` | **Redundant** — the continuation already declares the type; a stringly second copy invites drift between the name and the actual input type. Also widens the `ReadThen` decision surface (Q6: we want no new fields). |
| `QueryPlan` carries a type/schema name | **Mixes responsibilities** — `QueryPlan` is the *read intent* (which rows: `source`/`filters`/`projection`, `postgres_read.rs:53-60`); the row *type* is the *projection target* (how to shape the result). One `QueryPlan` may feed different continuations. Keep query and view-model separate. |
| Host config maps `source -> row type` | **Wrong authority + forbidden.** A `.ig` record is app *meaning*; operator-owned TOML must not declare app types. Host config owns *acquisition* (DSN, allowlist, field kinds), not app meaning. (Also: card boundary forbids host-config format changes.) |
| A dedicated `project`/projection contract | **Unneeded ceremony** — P1 already deferred projection contracts; a `map`/`filter` transform over `Collection[AppRow]` suffices. |

DX consequence: the app author writes exactly what `query_engine` / `batch_importer` already write today —
`type Row {…}` + `input rows : Collection[Row]` (`apps/igniter-apps/query_engine/eval.ig:74`,
`apps/igniter-apps/batch_importer/validate.ig:36`). **Zero new ceremony at the read site.**

---

## 3. How the host honors the type — load-time schema reconciliation (Q2)

The host's promise — "rows enter `.ig` already total + typed as `Collection[<AppRow>]`" — is made
**enforceable** by reconciling, for each projected source, the host's decoded field-kinds against the
`<AppRow>` field types. This is the schema-drift gate.

**What must match** (the assignability matrix — host decode-kind → permitted `<AppRow>` field type). It
mirrors the language's existing assignability (`structurally_assignable`, `typechecker.rs:3198`;
`text_arg_compatible` accepts `String` where `Text` is expected, `typechecker.rs:3567-3573`):

| Host `PostgresReadValueKind` (`postgres_read.rs:299-314`) | Permitted `<AppRow>` field type (v0) | Notes |
| --- | --- | --- |
| `Text` | `String` \| `Text` | the `text_arg_compatible` rule |
| `Integer` | `Integer` | exact, `i64` (`value.rs:55-62`) |
| `Boolean` | `Bool` | exact |
| `DecimalString` | `String` \| `Text` | v0 lossless string; typed `Decimal[s]` deferred (P2 §4, landing pad `value.rs:82-91`) |
| `Timestamp` | `String` \| `Text` | v0 RFC3339 string |
| `Json` | `Map[String, Unknown]` \| `String` | nested-record decode deferred (cross-source card) |
| `Array` | `Collection[String]` | v0 narrow; native arrays deferred |

Reconciliation rules:
1. every field of `<AppRow>` must be covered by the source's projected, allowlisted fields (no app field the
   host cannot supply);
2. each projected field's host kind must be assignable (table above) to the `<AppRow>` field of the same
   name;
3. extra host fields beyond `<AppRow>` are dropped by the materializer (cosmetic, not an error).

**When to reconcile.** Target: **load/boot**, fail-closed *before the listener binds* — exactly the posture
of `resolve_host_config` ("resolves every `*_env` before any socket bind",
`server/igniter-web/IMPLEMENTED_SURFACE.md:43`). A drift is then a **startup runner diagnostic** (§5), not a
per-request surprise — which is precisely the design bias ("don't put schema drift into app business logic").

**Implementation nuance (honest).** `ReadThen` plans are built dynamically in contract bodies, so statically
enumerating every `(source → continuation → row-type)` triple at boot is non-trivial. Two acceptable
postures, same fail-closed taxonomy, differing only in *when*:
- **boot reconciliation** where the `(source, continuation)` binding is statically recoverable (preferred);
- **first-dispatch reconciliation, cached** as the pragmatic v0 fallback (reconcile the first time a given
  continuation projects a given source; cache the verdict; drift → stable host error). Still off the app's
  business path; just discovered at first touch rather than boot.

The implementation card (§7) should prefer boot and may land first-dispatch-cached as the v0 step, clearly
labelled.

---

## 4. Provenance — `DatasetMeta` (Q3)

**Recommendation: yes, a fixed (non-generic) `DatasetMeta` crosses as a sibling continuation input.**

```text
type DatasetMeta {
  source    : String     -- logical source name (QueryPlan.source); app may branch/log on it
  count     : Integer    -- rows returned (postgres_read.rs:521 `count`)
  truncated : Bool       -- ← row_limit_clamped (postgres_read.rs:513,526); drives "load more" UX
}
```

Crossed as `input meta : DatasetMeta` beside `input rows : Collection[<AppRow>]`. It is a sibling, not a
wrapper, because user records are not generic — `Dataset[T] { rows, meta }` is **not expressible today**
(P1 §1.3, `lang/igniter-compiler/src/igweb.rs:63-68` uses only concrete `Collection[…]`). When user generics
land, `Dataset[T]` can unify the two — deferred.

Field decisions:
- **`effective_limit`** — **excluded** from v0. It is host-internal (the read cap); `truncated` is the
  *actionable* signal and `count` the *observable* one. (`effective_limit` exists at
  `postgres_read.rs:525` but stays host-side.)
- **`schema_version`** — **excluded** from v0. There is no schema registry; YAGNI. Add when a projected
  schema actually evolves and a consumer must branch on version.
- **Host-only, never crossed:** `plan_digest` (`read_dispatch.rs:23`), receipt id / `correlation_id`
  (`read_dispatch.rs:85-105`), DSN / capability id / scope (host-owned by construction). These are
  diagnostics/authority, not product data.

Principle: **provenance is *data*, not *control*** — `DatasetMeta` is a typed value the app *may* read, never
a new control-flow variant. (Q6 stays "no new `Decision` variants.")

---

## 5. Error taxonomy + HTTP/runner mapping (Q4, Q5)

Errors are placed where they are *actionable*. Schema concerns → operator/deploy (boot). Transport → host
request errors. Product semantics → app. **The app's business logic sees none of the schema cases.**

| Case | Detected | Owner | Surfaced as | Anchor |
| --- | --- | --- | --- | --- |
| Source/field not allowlisted; raw-SQL; op denied; bad predicate | request (gate) | Host | **403** / permanent | `postgres_read.rs:463-508`, `lib.rs:128-131` |
| **Host-kind ⇎ `<AppRow>`-type drift** (structural) | **boot** (or first-dispatch) | Host (config/app deploy) | **startup runner diagnostic** — new `DiagCode::ProjectionSchemaDrift`, non-zero exit, fail-closed before bind | new code in the `runner_diag.rs` scheme (`server/igniter-web/src/runner_diag.rs:26-79`) |
| Adapter unavailable / transient | request | Host | **503** | `postgres_read.rs:529-537`, `lib.rs:133-136` |
| Row missing a projected field / unexpected null, *post-reconciliation* (defense-in-depth; should not occur) | request | Host (broke its own promise) | **502** | proposed |
| Extra fields in a row | request | Host (materializer drops) | none (cosmetic) | P2 §4 |
| Truncated / clamped read | request | Host → app *data* | not an error — `meta.truncated = true` | `postgres_read.rs:513` |
| Empty result set | request | App (product decision) | **200 `[]`** | `todo_handlers.ig:344-357` |
| Not-found (single resource) | request | App | **404** | `todo_handlers.ig:171-181` |
| User request body / file / API payload mismatch | request | App (decoder) | **400** / `Result`/`RowResult` | `todo_handlers.ig:213-221`, `batch_importer/validate.ig:22-28` |

Status rationale (Q5):
- **Drift is a boot diagnostic, not a per-request status.** A structural mismatch between the host schema and
  the app row type is a *deployment* fact; it must fail the runner at startup with a stable `DiagCode`
  (exit-coded, redaction-safe), exactly like `CONFIG_RESOLVE` / `APP_BUILD`
  (`runner_diag.rs:53-79`, `IMPLEMENTED_SURFACE.md:113-120`). This is the single most important taxonomy
  decision: it keeps drift off every request path and out of `.ig`.
- **Residual per-request projection failure → 502**, not 500/422/503. It means the host's upstream data
  source returned something the host could not honor *as promised* — a gateway-level fault (distinct from
  503 *transient* and 403 *denied*). **Not 422** — 422 is for *client* request validation; host-owned rows
  are not client input. **Not 500** — 500 is unmapped/internal (`lib.rs:90-94,428-433`); a projection
  failure is a *defined* host condition, so it deserves a defined status.
- Product semantics (empty/not-found) stay app-owned (200/404), unchanged.

---

## 6. No new `Decision` variants (Q6)

**Confirmed: none.** `ReadThen { plan, then, carry }` is unchanged (`lang/igniter-compiler/src/igweb.rs:87`);
the continuation declares typed inputs as today; provenance crosses as a typed `DatasetMeta` value, not a
variant. The only host-side change the design implies is internal: a **structured** staged-read result
(P2 — cross rows + meta instead of `rows_json : String`) plus the boot reconciliation. The `.ig`-facing
decision grammar does not grow.

---

## 7. Host / app authority split (summary)

| Concern | Owner | Mechanism |
| --- | --- | --- |
| Which rows (source, filters, projection, bounds) | **App** declares intent; **Host** is authority | typed `QueryPlan` (`postgres_read.rs:53`); host allowlist + clamp gates |
| Field decode kinds (the schema) | **Host** | `PostgresReadPolicy.field_kinds` (`postgres_read.rs:328`) — schema authority |
| Row *type* / domain meaning | **App** | `type <AppRow>` + `input rows : Collection[<AppRow>]` (advisory mirror, `todo_handlers.ig:14`) |
| Schema ⇄ type reconciliation | **Host**, fail-closed | boot/first-dispatch assignability check → `DiagCode::ProjectionSchemaDrift` |
| Transform / view model | **App** | `map`/`filter`/`fold` over `Collection[<AppRow>]` (`todo_views.ig:138-148`) |
| Empty / not-found / 4xx product semantics | **App** | `Decision` (`Respond`/`RespondError`) |
| Provenance | **Host** produces; **App** may read | `DatasetMeta { source, count, truncated }` |

---

## 8. Smallest next implementation card

> Slots after the queued readiness cards P4 (transform-DX) / P5 (cross-source); fake-adapter, DB-free,
> harness-only; no `.igweb`/compiler/VM/Postgres/host-config change; no canon claim.

### `LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6` (implementation slice)

**Goal.** Cross fake-Postgres typed rows into a continuation as `Collection[TodoRow]` + `DatasetMeta`, with
host-side schema reconciliation, proving the §2–§5 contract end to end.

**Shape.**
- Host: structured staged-read result (P2 `materialize_rows`); cross `rows` (records) + `meta` (DatasetMeta);
  a `reconcile_projection(source_field_kinds, approw_input_type)` check (boot or first-dispatch-cached).
- App fixture: `type TodoRow {…}`, `type DatasetMeta {…}`, continuation
  `input rows : Collection[TodoRow]  input meta : DatasetMeta`.

**Acceptance** (sibling of `server/igniter-web/tests/todo_postgres_read_host_tests.rs`):
- [ ] Matched policy ⇄ `TodoRow` → continuation runs `filter(rows, r -> r.done == false)`,
      `map(rows, r -> r.title)`, `count(...)` over typed rows; Bool/Integer survive (not all-string).
- [ ] `meta.truncated == true` crosses on a clamped read (`limit > row cap`); `meta.count`/`meta.source`
      correct.
- [ ] **Deliberate kind drift** (host decodes `done` as `Text`, `TodoRow.done : Bool`) → **stable startup
      diagnostic `PROJECTION_SCHEMA_DRIFT`** (or first-dispatch host error), **never** a silent-wrong row in
      `.ig`. This test is the proof the shortcut was not taken.
- [ ] `map(rows, r -> call_contract("TodoLabel", r))` runs (join to the proven `Collection[HtmlNode]` view
      path).
- [ ] DB-free; `git diff --check` clean; no canon claim.

**Out of scope (named):** typed `Decimal`/`Timestamp` (P2 follow-on); nested `Json`→record; `Dataset[T]`
generic envelope (needs user generics); the read→HTML demo (P1 card P3 / pairs with this).

---

## Verification

```bash
rg -n "ReadThen|rows_json|carry|HostError|Denied|row_limit_clamped|effective_limit|PostgresReadValueKind|Request" \
  server/igniter-web runtime/igniter-machine lang/igniter-compiler \
  > /tmp/igniter-projection-contract-errors-grep.txt      # 824 hits

git diff --check                                            # clean
```

---

## Reporting

- **Projection contract choice:** the **continuation input type** `input rows : Collection[<AppRow>]` is the
  single declaration point; the host derives the spec from the compiled IR (`compiler.rs:213`). No
  `ReadThen`/`QueryPlan`/host-config row-type; no new `Decision` variant.
- **Error taxonomy headline:** **schema drift is a boot-time runner diagnostic
  (`DiagCode::ProjectionSchemaDrift`), not a per-request error**; transient → 503; gate denial → 403;
  residual host-promise violation → 502; empty/not-found stay app-owned (200/404). The app's business logic
  never sees schema concerns.
- **Meta / provenance choice:** a fixed `DatasetMeta { source, count, truncated }` crosses as a sibling
  input; `effective_limit`/`schema_version` excluded (v0); digests/receipts/DSN host-only. `Dataset[T]`
  deferred (no user generics).
- **Authority split:** host = schema authority (field kinds) + reconciliation enforcer; app = row type
  (advisory mirror) + transform + product semantics. The host honors `Collection[AppRow]` *by proof*, not
  by trust.
- **Next card:** `LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6` (host materializer + boot/first-dispatch
  reconciliation + `rows`/`meta` crossing), after the queued P4/P5 readiness cards.
