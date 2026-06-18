# lab-igniter-web-routing-pure-ig-p1-v0 — pure Igniter web routing shape

**Card:** `LAB-IGNITER-WEB-ROUTING-PURE-IG-P1` · **Delegation:** `OPUS-SERVER-WEB-DX-A`
**Status:** RESEARCH / READINESS (v0, recommended) — the smallest elegant **pure-Igniter** routing
shape that compiles to the existing `igniter-server` `ServerApp` protocol, without moving route tables
or domain meaning into Rust server core. **Design/pressure-test only. No code, no server-core router,
no compiler change, no DB/live, no canon claim for `.ig` web syntax.**
**Authority:** Lab research. Grounded in live `igniter-server` + `igniter-compiler` project mode + real
`.ig` apps (verified, not card lore).

---

## Executive summary

A pure-Igniter web app is **a compiled `.ig` capsule whose entry contract takes a request record and
returns a decision variant**, run behind the generic `igniter-server` host by a small **app-layer**
adapter. Routing is a `match`/`if` inside an `.ig` contract — never a Rust route table, never server
config.

```text
HTTP wire → igniter-server generic host (P1–P14 substrate)
  → IgWeb adapter (APP layer; dispatches the request record through the capsule)
  → pure .ig route contract:  Request → Decision variant
  → Decision JSON → ServerDecision (Respond | Invoke | InvokeEffect)
  → host executes through existing paths (Respond direct; Invoke/InvokeEffect via P3 MachineEffectHost)
```

The verdict: **the language already expresses HTTP routing + response composition as a pure,
exhaustive, fail-closed core** — proven by the existing `igniter-apps/web_router/` app. The one real
blocker for `/todos/:id`-style routing is **path-param extraction** (a known, registered language gap,
WR-P04), not anything about the server. v0 routes cleanly on exact paths, method, and host-tokenized
segments; true positional `:id` capture waits on a small stdlib/typing fix — named, not papered over.

---

## Live surface inventory (verified)

**Server (`igniter-server`, P1–P14 — see `…-wave-checkpoint-p14-v0.md`):** generic substrate;
`ServerApp::call(ServerRequest) -> ServerDecision` (`Respond | Invoke | InvokeEffect{target,input,
correlation_id,idempotency_key}`, no `capability_id`/`operation`/`scope`); host owns wire/loop/reload/
middleware + the optional `machine` effect bridge. Routing already lives in the app (a `match` in
`call`).

**Language / compiler (verified in real apps + stdlib):**
- **Types:** `type` records, sealed `variant` (ADT), `Integer`/`String`/`Float`/`Decimal[S]`/`Bool`,
  `Collection[T]`, `Map[K,V]`, `Option[T]` (`igniter-apps/*/types.ig`, `igniter-stdlib/stdlib/core/`).
- **Control flow:** `if/else`, exhaustive `match` with field binding (`reconciler/classify.ig`,
  `web_router/serve.ig`).
- **Strings (stdlib.text/core/string):** `split`, `starts_with`, `contains`, `concat`, `trim`,
  `length`, `byte_length`. **No** `substring`/`index_of`/regex.
- **Collections (stdlib.collections):** `map`/`filter`/`fold`/`first`/`last`/`count`/`any`/`all`/
  `range`/`take`/`concat`/`zip`. **No** positional `nth`/index.
- **Option:** `map_get`, `or_else`, `some`/`none`, monadic ops.
- **Composition:** `call_contract("Name", input)` for intra-app dispatch (`web_router/serve.ig:67-68`).
- **Project mode (`igniter-compiler/src/project.rs`):** `igniter.toml` `source_roots` (default `["."]`);
  modules indexed by PARSING each file's `module` declaration (never directory inference);
  `resolve_entry(root, entry_module)` resolves the transitive non-stdlib import closure →
  `multifile::compile_units`; `import stdlib.x.{…}` reserved/resolved from inventory; IDE **overlay**
  (unsaved-buffer) support already exists (`resolve_entry_with_overlays`, `OOF-PROJ-OVERLAY-*`);
  diagnostics `OOF-PROJ-ENTRY` / `OOF-IMP4` (dup module) / `OOF-IMP2` (missing import).

**Prior art (the pressure fixture already exists): `igniter-apps/web_router/`** — `HttpRequest{method,
path}` → routing in `Handle` (`if`+`starts_with`+`==`) → sealed `ContractResult` variant → `Respond`
(`match` → `HttpResponse{status,body}`) → `Serve` pipeline via `call_contract`. Its `PRESSURE_REGISTRY.md`
already registers every gap (WR-P01..P06) with stable language-issue codes. This packet builds on it.

---

## The 12 research questions

**Q1 — Layer boundary.** `IgWeb` is a **mix**, split cleanly:
- **Framework (pure `.ig` library + convention):** the request/decision *types* (`Request`,
  `Decision` variant) + tiny helper contracts. Lives in `.ig`, importable.
- **App (`.ig`):** the developer's route contracts + a single **route-entry contract** (`Serve`).
- **Adapter (Rust, APP/example layer — NOT server core):** a generic `ServerApp` impl that dispatches
  the request record through the compiled capsule and maps the returned `Decision` → `ServerDecision`.
  It depends on `igniter_machine` to run capsules, so it is **feature-gated like `effect_host`** and
  sits in the app/example layer, never `igniter-server/src`.
- **Host:** `igniter-server` substrate, unchanged.

**Q2 — Route representation.** Smallest v0 vocabulary, as DATA in `.ig` (no hidden config):
- **exact path** (`req.path == "/todos"`) — works today;
- **method dispatch** (`req.method == "GET"`) — works today;
- **prefix** (`starts_with(req.path,"/todos/")`) — works today;
- **segment arity + segment match** on a host-tokenized `segments: Collection[String]`
  (`count(segments)`, `first`/`last`, `or_else`) — works today for one trailing param;
- **path params (`/todos/:id`)** — positional capture is the gap (Q6);
- **fallback** — the final `else`/`match` arm → `NotFound`.
Routing is expressed as `if`/`match` in the entry contract; there is no separate route-table artifact.

**Q3 — Request algebra.** The entry contract receives one record. **Host-provided** (transport facts):
`method`, `path`, `segments` (generic `split(path,"/")` tokenization — NOT a route table), `query`
(Map), `headers` (Map), `body_json`, `correlation_id`, `idempotency_key`. **App-derived** (computed in
`.ig`): matched route, extracted params (within the Q6 limit), validation results. `segments` is
host-derived because `split` typing is currently a gap (Q6); tokenizing a path is generic normalization
the host already does for free, and carries no product meaning.

```igniter
type Request {
  method          : String
  path            : String
  segments        : Collection[String]   -- host: split(path, "/") minus empties
  correlation_id  : String
  idempotency_key : String
  body            : String                -- raw JSON; structured body parsing is app/stdlib work
}
```

**Q4 — Response algebra.** Pure `.ig` returns a sealed `Decision` variant that maps 1:1 to
`ServerDecision`. The app names only a **logical target** — never `capability_id`/`operation`/`scope`
(the same invariant the Rust protocol enforces):

```igniter
variant Decision {
  Respond      { status : Integer, body : String }
  Invoke       { target : String, input : String }                       -- input = JSON string (v0)
  InvokeEffect { target : String, input : String, idempotency_key : String }
}
```
The adapter `match`es this variant → `ServerDecision::{Respond|Invoke|InvokeEffect}` (parsing `input`
JSON, attaching `correlation_id`). `Respond` is mechanically identical to `web_router`'s proven
`match → HttpResponse{status,body}`.

**Q5 — Handler model.** Handlers are **plain contracts** composed by the entry contract via
`call_contract` (the live `web_router` shape). For Todo, the author writes:
`TodoIndex(req) -> Decision`, `TodoCreate(req) -> Decision`, `TodoShow(req) -> Decision`,
`TodoComplete(req) -> Decision`; the entry `Serve` routes `(method, path/segments)` to one of them.
Resource-style *grouping* is a future convenience, not required for v0 — explicit `call_contract`
dispatch is enough and keeps everything visible.

**Q6 — Path params (the gap, named honestly).** **Positional `:id` capture is NOT cleanly expressible
in pure `.ig` today.** Registered as **WR-P04**: `split(path,"/")` does not infer `Collection[String]`
(`OOF-TY1`), and `last(...)` returns a non-ergonomically-matchable `Option`; there is no `nth`/index,
`substring`, `index_of`, or regex. With host-provided `segments` you CAN do: arity (`count`), first/last
(`or_else(last(segments),"")`), so `/todos/:id` (2 segments, id = last) works — but `/todos/:id/done`
(3 segments, id = middle) needs positional `nth(segments, 1)`, which does not exist.
**Exact missing surface (do NOT paper over with a Rust router):**
1. `split(s,sep) -> Collection[String]` actually inferring `Collection[String]` (fix `OOF-TY1`);
2. `nth(Collection[T], Integer) -> Option[T]` (positional access);
3. ergonomic `Option` destructuring in `compute` (`LANG-SUMTYPE-CONSTRUCT-MATCH` for `Option`);
4. (optional) `substring`/`index_of` for in-segment parsing.
Until (1)–(3) land, v0 routes on exact path + method + segment arity + first/last; multi-param
positional routes are explicitly out.

**Q7 — State model.** Todo v0 is **pure request→response over fixture state**: handlers return
deterministic `Respond`/`InvokeEffect` decisions; there is **no persistence in this card**. Three tiers
(kept distinct): (a) **in-memory fixture** — the app returns canned/echoed data (v0, this wave);
(b) **Postgres capability** — a real read/write effect via `InvokeEffect{target}` wired host-side to the
proven Postgres-as-CapabilityExecutor (separate, gated; NOT here); (c) **future domain model** — an
`.ig` domain layer over (b). v0 touches only (a).

**Q8 — Project/import DX.** A small web app is a directory of `.ig` files, modules declared in-file:

```text
app/igniter.toml          # source_roots = ["app"]   (optional; default ".")
app/web/request.ig        # module IgWebRequest   — Request type
app/web/decision.ig       # module IgWebDecision  — Decision variant
app/todos/contracts.ig    # module TodoContracts  — TodoIndex/Create/Show/Complete
app/routes.ig             # module AppRoutes      — entry contract Serve(req) -> Decision
```
Compiled by **entry module**: `resolve_entry(root, "AppRoutes")` pulls the transitive non-stdlib
import closure → `compile_units` → an `.igapp`. This is exactly how `web_router` compiles
(`cargo run -- compile …`). IDE **overlay** support already lets an unsaved editor buffer flow through
resolution + compile (`resolve_entry_with_overlays`), so live diagnostics on an in-edit `routes.ig`
work without saving — directly useful for a web-app authoring IDE.

**Q9 — Adapter contract.** A generic Rust adapter (`IgAppServer`, app-layer, `machine` feature):
- **entry contract:** a declared route-entry name (default `"Serve"`), `Request -> Decision`;
- **input JSON:** the `Request` record (Q3), built by the adapter from `ServerRequest` (+ generic
  `segments` tokenization);
- **dispatch:** `IgniterMachine::dispatch(entry_contract, request_json)` (the same capsule-activation
  the machine already uses for `invoke`/effects);
- **output JSON:** the `Decision` variant → mapped to `ServerDecision` (parse `input` JSON for
  Invoke/InvokeEffect; attach `correlation_id`; for `InvokeEffect` the host then runs the proven P3
  `MachineEffectHost` path);
- **overlay/IDE:** because project mode already supports overlays, an IDE can compile-and-run an
  unsaved app buffer through the adapter for live preview.
The adapter holds **no route table** — it forwards one request record to one entry contract.

**Q10 — Rails analogy, without baggage.** Adopt: **declarative routes as data** (a `match` over
method/path is the route table, owned by the app), resource-style handler naming
(`Todo#index/create/show/complete`), convention-over-configuration *layout*. Reject: controller/global
mutable state (contracts are pure, `&self`-equivalent), an implicit DB ORM (effects are explicit
`InvokeEffect{target}`, host-authorized), server-owned route config (forbidden), and request/response
middleware magic (P8 middleware stays generic + route-agnostic).

**Q11 — Failure taxonomy → `ServerDecision`/`ServerResponse`.**
| Case | Where decided | Result |
|---|---|---|
| bad JSON body | **host/adapter** (before dispatch) | `Respond 400` (the capsule never sees malformed input) |
| unknown route | **app** (fallthrough arm) | `Decision::Respond{404}` |
| method not allowed | **app** (path matched, method didn't) | `Decision::Respond{405}` — the app distinguishes |
| validation failure | **app** | `Decision::Respond{400/422, body}` |
| missing idempotency key (effectful route) | **app** | `Decision::Respond{400}` (never a silent fresh effect — the SparkCRM/P10 lesson) |
| handler returns `Invoke`/`InvokeEffect` but host refuses (pool/auth) | **host** | existing `map_refusal` → 401/403/404/409/503 (P3) |
| effect outcome (committed/unknown/denied) | **host** | existing `map_effect_outcome` → 200/202/403/… (P3) |

**Q12 — Next implementation slice.** `LAB-IGNITER-WEB-ROUTING-TODO-P2` (fixture-only): one tiny Todo
`.ig` app (`Request`/`Decision` types + Todo handler contracts + `Serve` entry) compiled via project
mode, plus a generic `IgAppServer` adapter (app-layer, `machine` feature) that dispatches the request
record through `Serve` and maps `Decision → ServerDecision`. Tests: exact route, method dispatch (405),
segment routing for `/todos/:id` *within the Q6 limit* (route on `count`+`last`, and **document** that
`/todos/:id/done` middle-param capture is blocked on the WR-P04 fix — do not add a Rust route table),
not_found (404), idempotency propagation, and that decisions carry no effect identity. **No DB, no real
effects, no server-core routing.** If true positional `:id` is required first, the prerequisite is a
language card for WR-P04 (`split`→`Collection[String]` + `nth` + Option match), not a server change.

---

## Todo route sketch (pure `.ig`, honest about the gap)

```igniter
module AppRoutes
import IgWebRequest          -- Request
import IgWebDecision         -- Decision
import TodoContracts         -- TodoIndex / TodoCreate / TodoShow / TodoComplete
import stdlib.text.{ starts_with }
import stdlib.collections.{ count, last }
import stdlib.core.option.{ or_else }

pure contract Serve {
  input req : Request
  compute decision : Decision =
    if req.path == "/health" {
      Respond { status: 200, body: "ok" }
    } else {
      if req.path == "/todos" {
        if req.method == "GET"  { call_contract("TodoIndex",  req) }
        else { if req.method == "POST" { call_contract("TodoCreate", req) }
               else { Respond { status: 405, body: "Method Not Allowed" } } }
      } else {
        if starts_with(req.path, "/todos/") {
          -- segment routing within the Q6 limit (2 segments → id = last)
          if count(req.segments) == 2 {
            if req.method == "GET" { call_contract("TodoShow", req) }   -- TodoShow reads or_else(last(req.segments),"")
            else { Respond { status: 405, body: "Method Not Allowed" } }
          } else {
            -- /todos/:id/done : 3 segments, middle id → BLOCKED on WR-P04 (no nth). Documented, not faked.
            Respond { status: 501, body: "param capture not yet expressible (WR-P04)" }
          }
        } else {
          Respond { status: 404, body: "Not Found" }
        }
      }
    }
  output decision : Decision
}
```
(`TodoCreate` would `Respond 400` when `req.idempotency_key == ""`, else return
`InvokeEffect { target: "todo-create", input: req.body, idempotency_key: req.idempotency_key }`.)

---

## Current-language gaps (named, registered)

| Gap | Registry ID | Effect on web routing | Recommended fix-owner |
|---|---|---|---|
| `split` doesn't infer `Collection[String]`; no positional access | **WR-P04 / OOF-TY1** | no clean `:id` capture; multi-param routes blocked | language card: `split` typing + `nth(Collection[T],Integer)->Option[T]` |
| Option destructuring in `compute` is unergonomic | `LANG-SUMTYPE-CONSTRUCT-MATCH` (Option) | `first`/`last`/`map_get` results awkward to branch on | language ergonomics card |
| no `Map` construction in source | **WR-P03 / LANG-STDLIB-MAP** | response headers can't be built in `.ig` → **host injects headers** (v0 fine; response is status+body) | stdlib Map construction |
| record-literal inference (bare literals → Unknown in Rust) | **WR-P06 / LANG-RUBY-RECORD-LITERAL-INFERENCE** | use **annotated** `compute … : T = …` / match arms (already works) | inference card |
| no accept loop in pure core | **WR-P05 / PROP-037** | the serve loop is the host's job — **this is exactly what `igniter-server` provides** | already solved (server wave) |
| no `substring`/`index_of`/regex | — | no in-segment parsing (e.g. `id` numeric validation) in `.ig` | stdlib string card (optional) |

None of these are server gaps. The server boundary is correct; the gaps are small, localized language/
stdlib items, each already named with a stable ID.

---

## Closed surfaces (held)

No Rust router in `igniter-server`; no route-config format in server core; no web-framework dependency;
no canonical `.ig` web syntax claimed; no compiler-semantics change; no Postgres/persistence; no live
network/public listener; no SparkCRM/vendor shapes; no product/domain vocabulary in
`igniter-server/src`.

---

## Recommended P2 card

**`LAB-IGNITER-WEB-ROUTING-TODO-P2`** — fixture-only Todo `.ig` routing app + a generic app-layer
`IgAppServer` adapter (`machine` feature) dispatching `Serve(Request) -> Decision` → `ServerDecision`;
tests for exact route / method dispatch (405) / segment routing within the WR-P04 limit / 404 /
idempotency propagation / no effect identity; **no DB, no real effects, no server-core route table.**
Prerequisite for *true* `:id` capture is a separate language card (WR-P04), not a server change.

*(Optional discovery pointer: the server side of this stack is mapped in
`lab-docs/lang/lab-machine-igniter-server-wave-checkpoint-p14-v0.md`.)*

---

*Research/readiness only. Compiled 2026-06-18 against live `igniter-server`, `igniter-compiler`
project mode, `igniter-apps/web_router`, and `igniter-stdlib`.*
