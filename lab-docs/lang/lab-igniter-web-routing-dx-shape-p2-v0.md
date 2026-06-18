# lab-igniter-web-routing-dx-shape-p2-v0 — choosing the IgWeb routing authoring shape

**Card:** `LAB-IGNITER-WEB-ROUTING-DX-SHAPE-P2` · **Delegation:** `OPUS-SERVER-WEB-DX-B`
**Status:** RESEARCH / SHAPE-SELECTION (v0, recommended) — picks the developer-facing IgWeb routing
shape and rejects the rest with evidence. **Design only. No code, no compiler/parser/server change, no
canon `.ig` syntax, no DB/live.**
**Authority:** Lab research. Grounded in live compiler (`typechecker`/`emitter`), the `.igv` lowering
precedent, `igniter-apps/web_router`, and the P1 packet.

---

## 1. Executive summary — winner

**Winner: Shape C, realized as a lab `.igweb` declarative route DSL that LOWERS deterministically to an
explicit `Serve` (`Request → Decision`) `.ig` contract** — exactly the way `.igv` lowers to ViewArtifact
JSON today (`igniter-ui-kit/src/igv.rs::lower_igv`). Authoring is a tiny declarative block; the lowered
`.ig` is the committed, inspectable truth; the server is untouched.

```text
route GET  "/todos"          -> TodoIndex
route POST "/todos"          -> TodoCreate requires idempotency
route GET  "/todos/:id"      -> TodoShow
route POST "/todos/:id/done" -> TodoDone   requires idempotency
route GET  "/health"         -> Health
        │  lower_igweb  (deterministic lab pass; structured IgwebError{line,msg})
        ▼
pure contract Serve { input req : Request … match/if + STATIC call_contract arms … output decision : Decision }
        │  igniter-compiler project mode → .igapp → IgAppServer adapter
        ▼
ServerDecision (Respond | Invoke | InvokeEffect)
```

**Two hard facts decide this:**
1. **Igniter has NO dynamic dispatch.** `call_contract` resolves a **string-literal** contract name at
   compile time (`typechecker.rs:44`) and the emitter builds a **static function registry** ("no
   dynamic dispatch", `emitter.rs:128`). So a runtime route table that does
   `call_contract(route.target, req)` **cannot compile** and would discard exhaustiveness. Route
   targets MUST be statically lowered into explicit `match`/`if` arms. → kills Shape B; forbids the
   dynamic reading of C.
2. **Lowering sugar is a proven, in-tree pattern** (`.igv` → ViewArtifact, deterministic, lab-only, no
   compiler change). So a beautiful declarative authoring surface costs **a lab lowering tool, not a
   language change** — the honest way to get Rails-level readability without pretending Igniter is a
   general DSL.

**But beauty is GATED.** A clean Todo (and especially nested routes) needs path-param capture, which is
the registered language gap **WR-P04 / OOF-TY1**. So the shape is chosen now; the implementation is
sequenced **WR-P04 language fix first (P3), then the `.igweb` lowering + Todo proof (P4)**. This packet
**rejects P1's immediate `LAB-IGNITER-WEB-ROUTING-TODO-P2`** route (the card invited this) — building a
Todo adapter on top of prefix-only matching would freeze the ugly pattern.

---

## 2. Live surface inventory (verified this session)

- **No dynamic dispatch.** `call_contract("Name", …)` — name is a compile-time **literal** (every
  usage across `igniter-apps/*` is a literal: `advanced_logistics/example.ig`, `web_router/serve.ig:67`);
  `typechecker.rs:44` resolves it at compile time; `emitter.rs:128` builds a **static** VM registry.
- **`.igv` lowering precedent:** `igniter-ui-kit/src/igv.rs` — `lower_igv(src) -> Result<Value,
  IgvError>` (deterministic, sorted-key, `IgvError{line,msg}`), lab-only sugar over a proven artifact,
  **zero compiler change**. The template for `lower_igweb`.
- **Entrypoint metadata:** `EntrypointDecl` / `entrypoint_decl{target}` (`classifier.rs:25`,
  `emitter.rs:217-228`) — a single declared entry, not a route table; no fact-driven dispatch exists.
- **Language (from P1):** records, sealed `variant` + exhaustive `match`, `if/else`, `Collection`/`Map`/
  `Option`, stdlib `split`/`starts_with`/`concat`/`length`, `map`/`filter`/`fold`/`first`/`last`/`count`,
  `or_else`/`map_get`. **No** `nth`/`substring`/`index_of`/regex; `split` doesn't infer
  `Collection[String]` (WR-P04). Record literals need annotation (WR-P06). No Map construction (WR-P03).
- **Server (P1–P14):** generic; `ServerApp::call → ServerDecision`; routing already lives in the app;
  effect authority host-owned. Unchanged by this card.

---

## 3. Candidate sketches A–E

### Shape A — explicit `Serve` contract (`if`/`match` + `call_contract`)
The live `web_router` shape. *As lowered OUTPUT: excellent.* *As authoring SOURCE: ugly at scale* — 7
Todo routes are a 4-level nested `if/else` (P1 sketch); 20 routes are unreadable. Helper contracts
relieve the per-handler body but not the routing tree. **Verdict: the lowering TARGET, not the source.**

### Shape B — route records + dynamic dispatch
```igniter
type Route { method : String, pattern : String, target : String }
-- match a Route, then call_contract(route.target, req)   ← does NOT compile
```
**Verdict: REJECT.** Dynamic `call_contract(var)` is unsupported (static registry); it also turns
typed/exhaustive dispatch into stringly runtime dispatch — the opposite of Igniter's fail-closed value.

### Shape C — declarative route DSL → lowering (WINNER)
```text
route GET "/todos" -> TodoIndex
route POST "/todos" -> TodoCreate requires idempotency
```
A lab `.igweb` block lowered by `lower_igweb` (à la `lower_igv`) to Shape A's explicit `Serve`, with
each `-> Contract` becoming a **static** `call_contract("Contract", req)` arm. Declarative + readable +
typed/exhaustive (after lowering) + server-clean + proven lowering mechanism. **Verdict: WINNER as lab
sugar (NOT canon `.ig` syntax).**

### Shape D — Rails-like resource grouping
```text
resource todos { index GET "/todos" -> TodoIndex; show GET "/todos/:id" -> TodoShow; … }
```
**Verdict: adopt as OPTIONAL grouping sugar WITHIN C's DSL** (it lowers to the same flat route lines).
Keep it declaration-only — no controller object, no shared state, no implicit ORM, no before/after
filters. Grouping is cosmetic; if it ever grows behavior it becomes Rails baggage → forbidden.

### Shape E — host-tokenized route algebra
```igniter
type RouteMatch { method : String, resource : String, action : String, id : Option[String] }
```
**Verdict: PARTIAL / complement, not the authoring winner.** The generic-tokenization idea is right and
already in P1 (host provides `segments: Collection[String]` — pure tokenization, no route table). But a
host-built `RouteMatch{resource,action,id}` edges the host toward *interpreting* routes (which segment
is "resource" vs "action" is product meaning) → smuggles routing into the host. Keep the host to **raw
tokens only**; let the lowered `.ig` decide meaning. E does not solve WR-P04 (still needs `nth` for
middle params); it only relocates the same gap.

---

## 4. Pressure-fixture comparison

| Fixture | C (`.igweb`→`Serve`) today | After WR-P04 |
|---|---|---|
| **Todo basic** (`/todos`, `/todos/:id`, method 405, 404) | exact+method+single-trailing `:id` (via `segments`+`last`) ✓; 405/404 in lowered arms ✓ | clean `:id` binding ✓ |
| **Nested** `/accounts/:account_id/todos/:id` (+`/done`) | **BLOCKED — middle-param capture not expressible** (no `nth`; `last` only gets the trailing token). Bluntly: not doable today. | expressible (`split`→`Collection[String]` + `nth`) ✓ |
| **Webhook** `POST /webhooks/:vendor` + idempotency + no effect identity | vendor = trailing param ✓; `requires idempotency` lowers to keyless→400; decision = `InvokeEffect{target}` (no capability_id/op/scope) ✓ | unchanged ✓ |
| **Static** `GET /assets/app.css` | route MATCH ✓ but **serving verbatim bytes ✗** (wire body always JSON, P11) → belongs to the **assets/raw-response card**, NOT IgWeb routing v0 | unchanged (separate card) |

Honest blunt line: **nested middle-param routes are not expressible in pure `.ig` today**, and no
authoring shape can fake it without smuggling a Rust route table — which is forbidden. WR-P04 is the
real unlock.

---

## 5. Beauty score table (1–5)

| Criterion | A explicit | B dyn-records | **C DSL→lower** | D resource | E host-RouteMatch |
|---|---|---|---|---|---|
| Igniter-native | 5 | 2 | 4 | 4 | 4 |
| Explicit authority | 5 | 4 | 5 | 5 | 3 |
| Typed/exhaustive | 4 | 1 | 5 | 5 | 4 |
| Readable at 20 routes | 2 | 4 | 5 | 5 | 3 |
| Lowerable | 5 | 1 | 5 | 5 | 4 |
| Diagnosable | 4 | 2 | 4 | 4 | 3 |
| Server-clean | 5 | 5 | 5 | 5 | 4 |
| Future-friendly | 4 | 2 | 5 | 4 | 4 |
| **Total /40** | **34** | **21** | **38** | **37** | **29** |

C wins; D is C-with-grouping (fold into C); A is C's output; B and E lose. (B is also literally
uncompilable for dynamic dispatch.)

---

## 6. Recommended authoring pattern

A **lab-only `.igweb` route block** (Shape C, with D's `resource {}` as optional grouping) that lowers
to an explicit `Serve` `Request → Decision` contract:
- one `route METHOD "pattern" -> Contract [requires idempotency]` line per route;
- `requires idempotency` lowers to a keyless-guard arm (`idempotency_key == "" → Respond 400`);
- every `-> Contract` lowers to a **static** `call_contract("Contract", req)` arm — no dynamic dispatch;
- unmatched method on a matched path → `Respond 405`; no match → `Respond 404`;
- the generated `.ig` is **committed and inspectable** (sugar is convenience; `.ig` is the truth — the
  same discipline as `.igv`→ViewArtifact being byte-checked).
This is **not** canonical `.ig` syntax; it is lab sugar with a deterministic lowering and structured
diagnostics, exactly like `.igv`.

---

## 7. Lowering model

```text
app/routes.igweb        ── authoring (declarative routes; lab sugar, NOT canon)
   │ lower_igweb(src) -> Result<GeneratedIg, IgwebError{line,msg}>   (deterministic; mirrors lower_igv)
   ▼
app/routes.ig           ── generated explicit `Serve` (match/if + static call_contract arms +
   │                        segment/param binding); committed + inspectable
   │ igniter-compiler project mode: resolve_entry("AppRoutes") → compile_units
   ▼
app.igapp               ── compiled capsule
   │ IgAppServer adapter (app-layer, feature `machine`): dispatch Serve(Request) → Decision
   ▼
ServerDecision          ── Respond | Invoke | InvokeEffect  (host executes via existing paths)
```
The host provides the generic `Request` (incl. tokenized `segments`); it owns NO route table. The
lowering owns the route→arm mapping at authoring time, statically.

---

## 8. Language gaps (exact IDs)

| Gap | ID | Blocks | Owner |
|---|---|---|---|
| `split` doesn't infer `Collection[String]`; no positional access | **WR-P04 / OOF-TY1** | clean `:id`, ALL nested/middle params | language card (split typing + `nth(Collection[T],Integer)->Option[T]`) |
| Option destructuring in `compute` unergonomic | `LANG-SUMTYPE-CONSTRUCT-MATCH` (Option) | binding `first`/`last`/`nth` results | language ergonomics |
| no Map construction in source | **WR-P03 / LANG-STDLIB-MAP** | building response header maps in `.ig` (host injects v0) | stdlib (optional for routing) |
| record-literal inference | **WR-P06** | use annotated `compute … : T =` (already works) | inference (minor) |
| `.igweb` lowering tool | — (new lab tool, not a language feature) | the authoring sugar itself | `LAB-IGNITER-WEB-ROUTING-LOWERING-P4` |

The winning shape is clean **iff WR-P04 lands**. Everything else is either already fine or host-side.

---

## 9. Rejected shapes (why)

- **B (dynamic route records):** unsupported (`call_contract` is static-literal-only; static VM
  registry) and anti-exhaustive/anti-fail-closed. Reject outright.
- **A as AUTHORING source:** correct as the lowered target, but nested `if/else` at 20 routes is the
  exact ugliness this card exists to avoid. Keep as OUTPUT only.
- **E (host RouteMatch{resource,action,id}):** the structured-match part makes the **host** interpret
  route meaning (resource/action) — that is product routing leaking into the host. Keep host to generic
  `segments` tokens; reject host-side route semantics. (E doesn't even solve WR-P04.)
- **Pure-`.ig` routing as the authoring surface (hard Q1):** rejected — at scale it's the Shape-A
  nested-if problem. Routing authoring belongs in an adjacent `.igweb` sugar that lowers to `.ig`.

---

## 10. Hard questions (answered)

1. **Pure `.ig` the right authoring surface?** No for routing-at-scale. An adjacent `.igweb` sugar that
   lowers to `.ig` is right (mirrors `.igv`); pure-`.ig` `Serve` is the lowered target.
2. **Smallest honest sugar?** A line-oriented `.igweb` route block + a `lower_igweb` lab pass. No new
   canon syntax, no compiler change — it can't lie about language capability because it lowers to real,
   compiled `.ig` (and inherits WR-P04's limits visibly).
3. **Routes as facts consumed by a generic matcher?** Not at runtime — there is no dynamic/fact-driven
   dispatch (static registry). Routes are lowered **statically** into `match`/`if` arms. (A route
   artifact may exist as inspectable metadata, but dispatch is never fact-driven.)
4. **Dynamic `call_contract(route.target, req)` safe?** No — **unsupported** (compile-time literal +
   static registry) AND it would discard exhaustiveness. Targets MUST be statically lowered. This is
   both the only workable and the safest answer.
5. **Rails readability without Rails controllers?** Keep the DSL declaration-only (method/path/target/
   `requires idempotency`); handlers stay plain pure contracts; no controller object, no shared mutable
   state, no implicit ORM, no hidden filters. `resource {}` is cosmetic grouping that lowers away.
6. **Exact features for the winner to be clean?** WR-P04 (`split`→`Collection[String]`, OOF-TY1) +
   `nth(Collection[T],Integer)->Option[T]` + ergonomic Option `match` (`LANG-SUMTYPE-CONSTRUCT-MATCH`);
   plus the `lower_igweb` lab tool (not a language feature). WR-P03 only if responses need header maps.
7. **P3/P4 if "fix WR-P04 first"?** Yes — **P3 = `LAB-IGNITER-WEB-PATH-PARAMS-WR-P04-P3`** (language/
   stdlib: `split` typing + `nth` + Option-match ergonomics) is the prerequisite; **P4 =
   `LAB-IGNITER-WEB-ROUTING-LOWERING-P4`** (`.igweb` → `Serve` `.ig` lowering, mirroring `lower_igv`) +
   the fixture-only Todo proof once params work. Reject P1's immediate `TODO-P2`.

---

## Next cards (in order)

1. **`LAB-IGNITER-WEB-PATH-PARAMS-WR-P04-P3`** *(prerequisite, language/stdlib)* — make `split` infer
   `Collection[String]` (OOF-TY1), add `nth(Collection[T],Integer)->Option[T]`, and ergonomic `Option`
   destructuring in `compute`. Without it, no routing shape can express `:id`/nested params honestly.
2. **`LAB-IGNITER-WEB-ROUTING-LOWERING-P4`** *(then)* — the `.igweb` → explicit `Serve` `.ig` lowering
   tool (deterministic, structured diagnostics, mirrors `lower_igv`) + a fixture-only Todo proof through
   the P1 `IgAppServer` adapter. No server-core route table; no DB; no live.

(`LAB-IGNITER-WEB-ROUTING-TODO-P2` from P1 is **superseded** — do not implement Todo on prefix-only
matching.)

---

*Research/shape-selection only. Compiled 2026-06-18 against live compiler (`typechecker`/`emitter`),
`igniter-ui-kit/src/igv.rs`, `igniter-apps/web_router`, and the P1 packet. No code/compiler/server
change; no canon claim.*
